/*
 * Transparent DNS-over-HTTPS resolver for GoodbyeDPI.
 *
 * Outgoing UDP DNS queries are captured by the main WinDivert handle,
 * resolved via HTTPS (RFC 8484, application/dns-message, POST) in a worker
 * thread using WinHTTP and the answer is injected back to the system as an
 * inbound UDP packet coming from the original DNS server address.
 *
 * If DoH is not reachable (e.g. captive portal before login), the original
 * query is reinjected untouched and DoH is bypassed for a short period, so
 * the network login page keeps working.
 */
#include <winsock2.h>
#include <ws2tcpip.h>
#include <windows.h>
#include <winhttp.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "windivert.h"
#include "goodbyedpi.h"
#include "dohproxy.h"

#define DOH_MAX_SERVERS      8
#define DOH_MAX_INFLIGHT     128
#define DOH_TIMEOUT_MS       2500
#define DOH_FAIL_BACKOFF_MS  8000
#define DOH_MAX_RESP         4096
#define DOH_MAX_UDP_ANSWER   1400

typedef struct {
    wchar_t host[256];
    wchar_t path[128];
    INTERNET_PORT port;
    char display[320];
} doh_server_t;

typedef struct {
    HANDLE w_filter;
    WINDIVERT_ADDRESS addr;
    int is_v6;
    UINT packet_len;
    UINT ip_hdr_len;   /* IP header (+ IPv6 ext headers) length */
    UINT dns_offset;   /* offset of DNS payload in packet */
    UINT dns_len;
    UINT q_end;        /* end of question section inside DNS payload */
    char qname[256];
    unsigned char packet[];
} doh_job_t;

static doh_server_t servers[DOH_MAX_SERVERS];
static int server_count = 0;
static HINTERNET h_session = NULL;
static volatile LONG inflight = 0;
static volatile LONG preferred_server = 0;
static volatile ULONGLONG last_all_fail = 0;
static int doh_verbose = 0;

static const char *default_servers[] = {
    "1.1.1.1",
    "8.8.8.8",
    "1.0.0.1",
    "8.8.4.4",
    NULL
};

/* Domains which must always be resolved by the network's own DNS:
 * local names, reverse lookups and dormitory captive portal domains. */
static const char *doh_exempt_suffixes[] = {
    "local",
    "lan",
    "home",
    "localdomain",
    "internal",
    "intranet",
    "arpa",
    "gsb.gov.tr",
    "kyk.gov.tr",
    NULL
};

int doh_add_server(const char *server) {
    const char *p = server;
    const char *host_start, *host_end;
    const char *path = "/dns-query";
    unsigned long port = 443;
    doh_server_t *s;
    size_t i, hlen;

    if (!server || !*server || server_count >= DOH_MAX_SERVERS)
        return 1;

    if (_strnicmp(p, "https://", 8) == 0)
        p += 8;

    host_start = p;
    if (*p == '[') {
        host_end = strchr(p, ']');
        if (!host_end)
            return 1;
        host_end++;
    }
    else {
        host_end = p;
        while (*host_end && *host_end != ':' && *host_end != '/')
            host_end++;
    }

    hlen = (size_t)(host_end - host_start);
    if (hlen == 0 || hlen >= 255)
        return 1;

    p = host_end;
    if (*p == ':') {
        char *endptr = NULL;
        port = strtoul(p + 1, &endptr, 10);
        if (!endptr || port == 0 || port > 65535)
            return 1;
        p = endptr;
    }
    if (*p == '/')
        path = p;
    if (strlen(path) >= 127)
        return 1;

    s = &servers[server_count];
    memset(s, 0, sizeof(*s));
    for (i = 0; i < hlen; i++)
        s->host[i] = (wchar_t)(unsigned char)host_start[i];
    s->host[hlen] = L'\0';
    for (i = 0; path[i]; i++)
        s->path[i] = (wchar_t)(unsigned char)path[i];
    s->path[i] = L'\0';
    s->port = (INTERNET_PORT)port;
    snprintf(s->display, sizeof(s->display), "https://%.*s:%lu%s",
             (int)hlen, host_start, port, path);
    server_count++;
    return 0;
}

void doh_print_servers(void) {
    int i;
    for (i = 0; i < server_count; i++)
        printf("DoH server #%d: %s\n", i + 1, servers[i].display);
}

int doh_init(int verbose) {
    DWORD protocols;
    int i;

    doh_verbose = verbose;
    if (server_count == 0) {
        for (i = 0; default_servers[i]; i++)
            doh_add_server(default_servers[i]);
    }

    h_session = WinHttpOpen(L"GoodbyeDPI-DoH/1.0",
                            WINHTTP_ACCESS_TYPE_NO_PROXY,
                            WINHTTP_NO_PROXY_NAME,
                            WINHTTP_NO_PROXY_BYPASS, 0);
    if (!h_session) {
        printf("[DoH] WinHttpOpen failed: %lu\n", GetLastError());
        return 1;
    }
    WinHttpSetTimeouts(h_session, DOH_TIMEOUT_MS, DOH_TIMEOUT_MS,
                       DOH_TIMEOUT_MS, DOH_TIMEOUT_MS);

    /* Enable TLS 1.2 (+1.3 where supported) - required on Windows 7/8 */
#ifndef WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3
#define WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3 0x00002000
#endif
    protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2 | WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_3;
    if (!WinHttpSetOption(h_session, WINHTTP_OPTION_SECURE_PROTOCOLS,
                          &protocols, sizeof(protocols))) {
        protocols = WINHTTP_FLAG_SECURE_PROTOCOL_TLS1_2;
        WinHttpSetOption(h_session, WINHTTP_OPTION_SECURE_PROTOCOLS,
                         &protocols, sizeof(protocols));
    }
    return 0;
}

static int name_has_suffix(const char *name, const char *suffix) {
    size_t nlen = strlen(name);
    size_t slen = strlen(suffix);
    if (nlen < slen)
        return 0;
    if (nlen > slen && name[nlen - slen - 1] != '.')
        return 0;
    return _stricmp(name + (nlen - slen), suffix) == 0;
}

static int doh_is_exempt(const char *name) {
    int i;
    if (!name[0] || !strchr(name, '.'))
        return 1;
    for (i = 0; doh_exempt_suffixes[i]; i++) {
        if (name_has_suffix(name, doh_exempt_suffixes[i]))
            return 1;
    }
    return 0;
}

/* Parse standard query with a single question.
 * Returns 1 and fills name / question end offset if valid. */
static int dns_parse_query(const unsigned char *d, UINT len,
                           char *out, size_t outsz, UINT *q_end) {
    UINT p = 12;
    size_t o = 0;

    if (len < 17)
        return 0;
    if (d[2] & 0x80)            /* QR = response */
        return 0;
    if ((d[2] >> 3) & 0x0F)     /* OPCODE != QUERY */
        return 0;
    if (d[4] != 0 || d[5] != 1) /* QDCOUNT != 1 */
        return 0;

    for (;;) {
        UINT l, i;
        if (p >= len)
            return 0;
        l = d[p];
        if (l == 0) {
            p++;
            break;
        }
        if (l & 0xC0)
            return 0;
        if (p + 1 + l > len)
            return 0;
        if (o && o < outsz - 1)
            out[o++] = '.';
        for (i = 0; i < l; i++) {
            unsigned char c = d[p + 1 + i];
            if (c >= 'A' && c <= 'Z')
                c = (unsigned char)(c + ('a' - 'A'));
            if (o < outsz - 1)
                out[o++] = (char)c;
        }
        p += 1 + l;
    }
    out[o] = '\0';
    if (p + 4 > len)
        return 0;
    *q_end = p + 4;
    return 1;
}

static int doh_query(const doh_server_t *s, const unsigned char *query, DWORD qlen,
                     unsigned char *resp, DWORD *resp_len) {
    static const wchar_t headers[] =
        L"Content-Type: application/dns-message\r\n"
        L"Accept: application/dns-message\r\n";
    HINTERNET h_connect = NULL, h_request = NULL;
    DWORD status = 0, status_size = sizeof(status);
    DWORD total = 0, avail = 0, read = 0;
    int ok = 0;

    *resp_len = 0;
    h_connect = WinHttpConnect(h_session, s->host, s->port, 0);
    if (!h_connect)
        goto out;
    h_request = WinHttpOpenRequest(h_connect, L"POST", s->path, NULL,
                                   WINHTTP_NO_REFERER,
                                   WINHTTP_DEFAULT_ACCEPT_TYPES,
                                   WINHTTP_FLAG_SECURE);
    if (!h_request)
        goto out;
    if (!WinHttpSendRequest(h_request, headers, (DWORD)-1L,
                            (LPVOID)query, qlen, qlen, 0))
        goto out;
    if (!WinHttpReceiveResponse(h_request, NULL))
        goto out;
    if (!WinHttpQueryHeaders(h_request,
                             WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                             WINHTTP_HEADER_NAME_BY_INDEX, &status, &status_size,
                             WINHTTP_NO_HEADER_INDEX) || status != 200)
        goto out;

    for (;;) {
        if (!WinHttpQueryDataAvailable(h_request, &avail))
            goto out;
        if (avail == 0)
            break;
        if (total + avail > DOH_MAX_RESP)
            goto out;
        if (!WinHttpReadData(h_request, resp + total, avail, &read))
            goto out;
        if (read == 0)
            break;
        total += read;
    }
    if (total >= 12 && (resp[2] & 0x80)) {
        *resp_len = total;
        ok = 1;
    }

out:
    if (h_request)
        WinHttpCloseHandle(h_request);
    if (h_connect)
        WinHttpCloseHandle(h_connect);
    return ok;
}

static void doh_inject_answer(doh_job_t *job, unsigned char *resp, DWORD resp_len) {
    unsigned char out[MAX_PACKET_SIZE];
    const unsigned char *query = job->packet + job->dns_offset;
    WINDIVERT_ADDRESS addr = job->addr;
    PWINDIVERT_UDPHDR udp;
    UINT out_len;

    /* Keep the original transaction ID */
    resp[0] = query[0];
    resp[1] = query[1];

    if (resp_len > DOH_MAX_UDP_ANSWER) {
        /* Too big for a single UDP datagram: answer with TC bit set,
         * containing only the original question. */
        memcpy(resp, query, job->q_end);
        resp[2] = (unsigned char)(0x80 | 0x02 | (query[2] & 0x01)); /* QR, TC, RD */
        resp[3] = 0x80;                                             /* RA */
        resp[6] = resp[7] = resp[8] = resp[9] = resp[10] = resp[11] = 0;
        resp_len = job->q_end;
    }

    out_len = job->ip_hdr_len + 8 + resp_len;
    if (out_len > sizeof(out))
        return;

    memcpy(out, job->packet, job->ip_hdr_len + 8);
    if (!job->is_v6) {
        PWINDIVERT_IPHDR ip = (PWINDIVERT_IPHDR)out;
        UINT32 tmp = ip->SrcAddr;
        ip->SrcAddr = ip->DstAddr;
        ip->DstAddr = tmp;
        ip->Length = htons((u_short)out_len);
        ip->TTL = 64;
        ip->Checksum = 0;
    }
    else {
        PWINDIVERT_IPV6HDR ip6 = (PWINDIVERT_IPV6HDR)out;
        UINT32 tmp[4];
        memcpy(tmp, ip6->SrcAddr, sizeof(tmp));
        memcpy(ip6->SrcAddr, ip6->DstAddr, sizeof(tmp));
        memcpy(ip6->DstAddr, tmp, sizeof(tmp));
        ip6->Length = htons((u_short)(out_len - 40));
        ip6->HopLimit = 64;
    }

    udp = (PWINDIVERT_UDPHDR)(out + job->ip_hdr_len);
    {
        UINT16 tmp_port = udp->SrcPort;
        udp->SrcPort = udp->DstPort;
        udp->DstPort = tmp_port;
    }
    udp->Length = htons((u_short)(8 + resp_len));
    udp->Checksum = 0;
    memcpy(out + job->ip_hdr_len + 8, resp, resp_len);

    addr.Outbound = 0;
    addr.IPChecksum = 0;
    addr.TCPChecksum = 0;
    addr.UDPChecksum = 0;
    WinDivertHelperCalcChecksums(out, out_len, &addr, 0);
    if (!WinDivertSend(job->w_filter, out, out_len, NULL, &addr)) {
        if (doh_verbose)
            printf("[DoH] Inject failed for %s: %lu\n", job->qname, GetLastError());
    }
}

static DWORD WINAPI doh_worker(LPVOID param) {
    doh_job_t *job = (doh_job_t *)param;
    unsigned char resp[DOH_MAX_RESP];
    DWORD resp_len = 0;
    const unsigned char *query = job->packet + job->dns_offset;
    LONG first = preferred_server;
    ULONGLONG t0 = GetTickCount64();
    int ok = 0, k, used = -1;

    for (k = 0; k < server_count && !ok; k++) {
        int si = (int)((first + k) % server_count);
        if (doh_query(&servers[si], query, job->dns_len, resp, &resp_len)) {
            ok = 1;
            used = si;
            if (si != first)
                InterlockedExchange(&preferred_server, si);
        }
    }

    if (ok) {
        last_all_fail = 0;
        doh_inject_answer(job, resp, resp_len);
        if (doh_verbose)
            printf("[DoH] %s -> OK via %s (%llu ms)\n", job->qname,
                   servers[used].display, GetTickCount64() - t0);
    }
    else {
        last_all_fail = GetTickCount64();
        /* Fall back to the network DNS: reinject original query */
        WinDivertSend(job->w_filter, job->packet, job->packet_len, NULL, &job->addr);
        if (doh_verbose)
            printf("[DoH] %s -> FAILED, using network DNS (%llu ms)\n",
                   job->qname, GetTickCount64() - t0);
    }

    free(job);
    InterlockedDecrement(&inflight);
    return 0;
}

int doh_handle_outgoing(HANDLE w_filter, const char *packet, UINT packetLen,
                        const WINDIVERT_ADDRESS *addr,
                        int is_v6, const char *dns_data, UINT dns_len) {
    char name[256];
    UINT q_end = 0;
    UINT dns_offset;
    doh_job_t *job;
    HANDLE thread;

    if (!h_session || server_count == 0)
        return 0;
    if (!dns_data || dns_len < 17 || dns_len > 1232)
        return 0;
    if (!dns_parse_query((const unsigned char *)dns_data, dns_len, name, sizeof(name), &q_end))
        return 0;
    if (doh_is_exempt(name))
        return 0;
    if (last_all_fail && GetTickCount64() - last_all_fail < DOH_FAIL_BACKOFF_MS)
        return 0;

    dns_offset = (UINT)(dns_data - packet);
    if (dns_offset < 8 + (is_v6 ? 40u : 20u) || dns_offset + dns_len > packetLen)
        return 0;

    if (InterlockedIncrement(&inflight) > DOH_MAX_INFLIGHT) {
        InterlockedDecrement(&inflight);
        return 0;
    }

    job = (doh_job_t *)malloc(sizeof(doh_job_t) + packetLen);
    if (!job) {
        InterlockedDecrement(&inflight);
        return 0;
    }
    job->w_filter = w_filter;
    job->addr = *addr;
    job->is_v6 = is_v6;
    job->packet_len = packetLen;
    job->dns_offset = dns_offset;
    job->ip_hdr_len = dns_offset - 8;
    job->dns_len = dns_len;
    job->q_end = q_end;
    memcpy(job->qname, name, sizeof(job->qname));
    memcpy(job->packet, packet, packetLen);

    thread = CreateThread(NULL, 0, doh_worker, job, 0, NULL);
    if (!thread) {
        free(job);
        InterlockedDecrement(&inflight);
        return 0;
    }
    CloseHandle(thread);
    return 1;
}
