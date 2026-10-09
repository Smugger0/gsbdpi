#ifndef _DOHPROXY_H
#define _DOHPROXY_H

#include <windows.h>
#include "windivert.h"

/*
 * Transparent DNS-over-HTTPS (DoH) resolver.
 *
 * Some networks (e.g. Turkish GSB/KYK dormitories) transparently hijack
 * every plain UDP DNS packet, regardless of destination address or port,
 * and answer blocked domains with a fake IP. --dns-addr redirection is
 * useless there. This module intercepts outgoing UDP/53 DNS queries,
 * resolves them over HTTPS (RFC 8484) via WinHTTP and injects the answer
 * back as an inbound UDP packet, so every application on the system gets
 * the real answer without any system configuration change.
 */

/* Add DoH server (IP address or host name, optional ":port", optional "/path").
 * Returns 0 on success. */
int doh_add_server(const char *server);

/* Initialize module. Adds default servers if none were added.
 * Returns 0 on success. */
int doh_init(int verbose);

/* Handle an outgoing UDP packet with payload.
 * Returns 1 if the packet was consumed (caller must NOT reinject it),
 * 0 if it should be processed/reinjected as usual. */
int doh_handle_outgoing(HANDLE w_filter, const char *packet, UINT packetLen,
                        const WINDIVERT_ADDRESS *addr,
                        int is_v6, const char *dns_data, UINT dns_len);

/* Print server list */
void doh_print_servers(void);

#endif
