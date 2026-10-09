#define _CRT_SECURE_NO_WARNINGS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

#define TOOL_VERSION "v1.3.0"

/* Console Colors */
#define COL_RESET   7
#define COL_CYAN    11
#define COL_GREEN   10
#define COL_RED     12
#define COL_YELLOW  14
#define COL_GRAY    8
#define COL_WHITE   15

static HANDLE hConsole = NULL;

static void set_color(int color) {
    if (hConsole) SetConsoleTextAttribute(hConsole, (WORD)color);
}

static void print_title(const char *title) {
    set_color(COL_CYAN);
    printf("\n=======================================================================\n");
    printf("  %s\n", title);
    printf("=======================================================================\n");
    set_color(COL_RESET);
}

static void print_ok(const char *msg) {
    set_color(COL_GREEN);
    printf("  [ OK ] ");
    set_color(COL_WHITE);
    printf("%s\n", msg);
    set_color(COL_RESET);
}

static void print_bad(const char *msg) {
    set_color(COL_RED);
    printf("  [HATA] ");
    set_color(COL_WHITE);
    printf("%s\n", msg);
    set_color(COL_RESET);
}

static void print_warn(const char *msg) {
    set_color(COL_YELLOW);
    printf("  [UYARI] ");
    set_color(COL_WHITE);
    printf("%s\n", msg);
    set_color(COL_RESET);
}

static void print_info(const char *msg) {
    set_color(COL_GRAY);
    printf("  [BILGI] %s\n", msg);
    set_color(COL_RESET);
}

/* Check Administrator Privileges */
static BOOL is_admin(void) {
    BOOL elevated = FALSE;
    HANDLE hToken = NULL;
    if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &hToken)) {
        TOKEN_ELEVATION elevation;
        DWORD cbSize = sizeof(TOKEN_ELEVATION);
        if (GetTokenInformation(hToken, TokenElevation, &elevation, sizeof(elevation), &cbSize)) {
            elevated = elevation.TokenIsElevated;
        }
        CloseHandle(hToken);
    }
    return elevated;
}

/* Relaunch as Admin using ShellExecuteEx */
static void relaunch_as_admin(int argc, char *argv[]) {
    char exePath[MAX_PATH];
    GetModuleFileNameA(NULL, exePath, MAX_PATH);

    char params[2048] = "";
    for (int i = 1; i < argc; i++) {
        strcat(params, "\"");
        strcat(params, argv[i]);
        strcat(params, "\" ");
    }

    SHELLEXECUTEINFOA sei = { sizeof(sei) };
    sei.lpVerb = "runas";
    sei.lpFile = exePath;
    sei.lpParameters = params;
    sei.nShow = SW_SHOWNORMAL;

    if (ShellExecuteExA(&sei)) {
        exit(0);
    } else {
        print_bad("Yonetici izni verilemedi. Lutfen sag tiklayip 'Yonetici olarak calistir' secin.");
        printf("\nDevam etmek icin ENTER tusuna basin...");
        getchar();
        exit(1);
    }
}

/* Kill any running goodbyedpi process */
static void kill_goodbyedpi(void) {
    system("taskkill /f /im goodbyedpi.exe >nul 2>&1");
}

/* Execute command and get output */
static int exec_cmd_output(const char *cmd, char *out, size_t outsz) {
    FILE *fp = _popen(cmd, "r");
    if (!fp) return -1;
    if (out && outsz > 0) {
        out[0] = '\0';
        size_t n = fread(out, 1, outsz - 1, fp);
        out[n] = '\0';
    }
    return _pclose(fp);
}

/* Single HTTP Probe using curl */
typedef struct {
    char host[128];
    char real_ip[64];
    int ok;
    int http_code;
    int curl_code;
    double time_total;
    char reason[128];
} probe_result_t;

static probe_result_t probe_target(const char *host, const char *path, const char *ip, int timeout_sec) {
    probe_result_t r;
    memset(&r, 0, sizeof(r));
    strncpy(r.host, host, sizeof(r.host) - 1);
    if (ip) strncpy(r.real_ip, ip, sizeof(r.real_ip) - 1);

    char cmd[1024];
    if (ip && strlen(ip) > 0) {
        snprintf(cmd, sizeof(cmd),
            "curl.exe -s -o NUL -m %d --connect-timeout 4 "
            "--resolve \"%s:443:%s\" "
            "-A \"Mozilla/5.0 GSBDPI-Test\" "
            "-w \"%%{http_code} %%{time_total}\" "
            "\"https://%s%s\" 2>&1",
            timeout_sec, host, ip, host, path);
    } else {
        snprintf(cmd, sizeof(cmd),
            "curl.exe -s -o NUL -m %d --connect-timeout 4 "
            "-A \"Mozilla/5.0 GSBDPI-Test\" "
            "-w \"%%{http_code} %%{time_total}\" "
            "\"https://%s%s\" 2>&1",
            timeout_sec, host, path);
    }

    char out[256];
    int exit_code = exec_cmd_output(cmd, out, sizeof(out));
    r.curl_code = exit_code;

    int http = 0;
    double t = 0.0;
    if (sscanf(out, "%d %lf", &http, &t) >= 1) {
        r.http_code = http;
        r.time_total = t;
    }

    if (exit_code == 0 && r.http_code != 0) {
        r.ok = 1;
        snprintf(r.reason, sizeof(r.reason), "HTTP %d (%.2fs)", r.http_code, r.time_total);
    } else {
        r.ok = 0;
        switch (exit_code) {
            case 6:  strcpy(r.reason, "DNS cozulemedi"); break;
            case 7:  strcpy(r.reason, "Baglanti reddedildi"); break;
            case 28: strcpy(r.reason, "Zaman asimi"); break;
            case 35: strcpy(r.reason, "TLS sifirlandi (DPI engeli)"); break;
            case 52: strcpy(r.reason, "Bos yanit"); break;
            case 56: strcpy(r.reason, "Baglanti sifirlandi (DPI engeli)"); break;
            case 60: strcpy(r.reason, "Sertifika hatasi"); break;
            default: snprintf(r.reason, sizeof(r.reason), "curl hata %d", exit_code); break;
        }
    }
    return r;
}

/* Strategy Definition */
typedef struct {
    const char *id;
    const char *name;
    const char *args;
    const char *desc_why;
    int safe;
    int passed;
    int total;
    int controls_ok;
    double avg_time;
    char error[256];
} strategy_t;

static strategy_t strategies[] = {
    { 
        "kyk",
        "Yeni KYK Modu (Reverse-Frag + TTL 5 + DoH + Beyaz Liste)",
        "--kyk",
        "Mod 5'in TTL 5 fake packet teknolojisi + Seffaf DoH + Yurt Portali Guvenligi.",
        1, 0, 0, 1, 0.0, ""
    },
    { 
        "m5ttl5",
        "Mod -5 + Sabit TTL 5 (TTNET / KYK Hızlı Mod)",
        "-5 --set-ttl 5 -q --doh",
        "TTL=5 sahte paketle TTNET/GSB DPI motorunu aldatir, gercek paket süzgeçten gecer.",
        0, 0, 0, 1, 0.0, ""
    },
    { 
        "m5",
        "Mod -5 (Auto-TTL Sahte Paket)",
        "-5 -q --doh",
        "DPI hop mesafesini otomatik hesaplayarak sahte paket yollar.",
        0, 0, 0, 1, 0.0, ""
    },
    { 
        "ttl3",
        "Mod -5 + Düşük TTL 3 (Mesafe Yetersizlik Testi)",
        "-5 --set-ttl 3 -q --doh",
        "TTL 3 az gelirse sahte paket DPI'a ulasamadan duser ve DPI engeli devam eder.",
        0, 0, 0, 1, 0.0, ""
    },
    { 
        "sni",
        "Saf SNI Parçalama (--frag-by-sni, Sahte Paketsiz)",
        "-q --native-frag -f 2 -e 2 --frag-by-sni --doh",
        "Sahte paketsiz sadece parcalama yapar. Stateful DPI akisi birlestirdigi icin takilir.",
        1, 0, 0, 1, 0.0, ""
    },
    { 
        "m9",
        "Mod -9 (Wrong-Seq + Wrong-Checksum)",
        "-9 --doh",
        "Bozuk checksum gonderir. KYK kurumsal router'lari bozuk paketleri çöpe atar (drop).",
        0, 0, 0, 1, 0.0, ""
    }
};
#define STRATEGY_COUNT (sizeof(strategies) / sizeof(strategies[0]))

/* Test Targets */
typedef struct {
    const char *host;
    const char *path;
    const char *fallback_ip;
} target_site_t;

static target_site_t targets[] = {
    { "discord.com",         "/",            "162.159.138.232" },
    { "gateway.discord.gg",  "/",            "162.159.135.234" },
    { "cdn.discordapp.com",  "/",            "162.159.129.233" },
    { "updates.discord.com", "/",            "162.159.138.232" },
    { "pastebin.com",        "/",            "172.66.40.172"   }
};
#define TARGET_COUNT (sizeof(targets) / sizeof(targets[0]))

static target_site_t controls[] = {
    { "www.cloudflare.com",  "/",            "104.16.123.96"   },
    { "www.google.com",      "/generate_204", "142.250.187.100" }
};
#define CONTROL_COUNT (sizeof(controls) / sizeof(controls[0]))

/* Start GoodbyeDPI as a child process */
static PROCESS_INFORMATION start_goodbyedpi(const char *exe_path, const char *args) {
    PROCESS_INFORMATION pi = { 0 };
    STARTUPINFOA si = { sizeof(si) };
    si.dwFlags = STARTF_USESHOWWINDOW;
    si.wShowWindow = SW_HIDE;

    char cmdline[2048];
    snprintf(cmdline, sizeof(cmdline), "\"%s\" %s", exe_path, args);

    if (CreateProcessA(NULL, cmdline, NULL, NULL, FALSE, CREATE_NO_WINDOW, NULL, NULL, &si, &pi)) {
        Sleep(750); /* give WinDivert time to initialize and hook filter */
    }
    return pi;
}

static void stop_process(PROCESS_INFORMATION *pi) {
    if (pi && pi->hProcess) {
        TerminateProcess(pi->hProcess, 0);
        WaitForSingleObject(pi->hProcess, 1500);
        CloseHandle(pi->hProcess);
        CloseHandle(pi->hThread);
        pi->hProcess = NULL;
    }
    kill_goodbyedpi();
}

int main(int argc, char *argv[]) {
    hConsole = GetStdHandle(STD_OUTPUT_HANDLE);

    /* UTF-8 console output */
    SetConsoleOutputCP(65001);

    printf("\n");
    set_color(COL_CYAN);
    printf("   =================================================================\n");
    printf("     GSB / KYK GOODBYEDPI OTOMATIK STRATEJI VE TEST ARACI (%s)\n", TOOL_VERSION);
    printf("     Turk Telekom / KYK Guvenlik Duvari Otomatik Teshis Araci\n");
    printf("   =================================================================\n");
    set_color(COL_RESET);

    /* Elevation check */
    if (!is_admin()) {
        print_warn("Yonetici haklari tespit edilmedi. UAC onay penceresi aciliyor...");
        relaunch_as_admin(argc, argv);
        return 0;
    }
    print_ok("Yonetici izni dogrulandi.");

    /* Locate goodbyedpi.exe */
    char rootDir[MAX_PATH];
    GetModuleFileNameA(NULL, rootDir, MAX_PATH);
    char *pLastSlash = strrchr(rootDir, '\\');
    if (pLastSlash) *pLastSlash = '\0';

    char exePath[MAX_PATH];
    snprintf(exePath, sizeof(exePath), "%s\\x86_64\\goodbyedpi.exe", rootDir);
    if (GetFileAttributesA(exePath) == INVALID_FILE_ATTRIBUTES) {
        snprintf(exePath, sizeof(exePath), "%s\\goodbyedpi_src\\src\\goodbyedpi.exe", rootDir);
    }
    if (GetFileAttributesA(exePath) == INVALID_FILE_ATTRIBUTES) {
        print_bad("goodbyedpi.exe bulunamadi!");
        printf("\nDevam etmek icin ENTER tusuna basin...");
        getchar();
        return 1;
    }
    print_ok("GoodbyeDPI calistirma motoru hazir.");

    kill_goodbyedpi();

    /* -------------------------------------------------------------
     * 1. Ag Analizi
     * ------------------------------------------------------------- */
    print_title("1/3  AG VE FILTRELEME ANALIZI");

    /* DNS Gasp Testi */
    char dnsOut[256];
    int hijack = 0;
    if (exec_cmd_output("nslookup -timeout=2 1.1.1.1 192.0.2.1 2>&1", dnsOut, sizeof(dnsOut)) == 0) {
        if (strstr(dnsOut, "Address") || strstr(dnsOut, "1.1.1.1")) {
            hijack = 1;
        }
    }
    if (hijack) {
        print_warn("DNS Gaspi (Hijack) Tespit Edildi: Yurt agi tum UDP/53 sorgularini ele geciriyor.");
        print_info("-> Cozum: Dahili DoH (DNS-over-HTTPS) devrede tutulmalidir.");
    } else {
        print_ok("Standart DNS yapisi tespit edildi.");
    }

    /* DoH Testi */
    char dohOut[512];
    int doh_ok = 0;
    exec_cmd_output("curl.exe -s -m 4 -H \"accept: application/dns-json\" \"https://1.1.1.1/dns-query?name=discord.com&type=A\" 2>&1", dohOut, sizeof(dohOut));
    if (strstr(dohOut, "\"data\"") || strstr(dohOut, "162.159.")) {
        doh_ok = 1;
        print_ok("DoH (Cloudflare 1.1.1.1 HTTPS) erisilebilir! (Sistemin DNS'i guvende)");
    } else {
        print_warn("DoH 1.1.1.1 erisilemedi, Google 8.8.8.8 deneniyor...");
        exec_cmd_output("curl.exe -s -m 4 \"https://8.8.8.8/resolve?name=discord.com&type=A\" 2>&1", dohOut, sizeof(dohOut));
        if (strstr(dohOut, "\"data\"")) {
            doh_ok = 1;
            print_ok("DoH (Google 8.8.8.8 HTTPS) erisilebilir!");
        } else {
            print_bad("DoH erisilemiyor.");
        }
    }

    /* Baseline Block Test */
    print_info("Mevcut durumda (GoodbyeDPI kapaliyken) siteler test ediliyor...");
    int blocked_count = 0;
    for (size_t i = 0; i < TARGET_COUNT; i++) {
        probe_result_t pr = probe_target(targets[i].host, targets[i].path, targets[i].fallback_ip, 4);
        if (!pr.ok) {
            blocked_count++;
            set_color(COL_RED);
            printf("      %-22s : %s\n", targets[i].host, pr.reason);
            set_color(COL_RESET);
        } else {
            set_color(COL_GREEN);
            printf("      %-22s : %s\n", targets[i].host, pr.reason);
            set_color(COL_RESET);
        }
    }
    if (blocked_count > 0) {
        print_warn("Yurdunuzda SNI / TLS engellemesi devrede! DPI atlatma stratejisi gereklidir.");
    } else {
        print_ok("Dogrudan IP ile engelli site bulunmuyor.");
    }

    /* -------------------------------------------------------------
     * 2. Strateji Testleri
     * ------------------------------------------------------------- */
    print_title("2/3  DPI ATLATMA STRATEJILERI TEST EDILIYOR");
    printf("  Farkli DPI baypas mekanizmalari sirayla deneniyor...\n\n");

    strategy_t *best_strat = NULL;

    for (size_t i = 0; i < STRATEGY_COUNT; i++) {
        strategy_t *st = &strategies[i];
        set_color(COL_WHITE);
        printf("  [%d/%d] %s\n", (int)(i + 1), (int)STRATEGY_COUNT, st->name);
        set_color(COL_GRAY);
        printf("        Parametre : goodbyedpi.exe %s\n", st->args);
        printf("        Mekanizma : %s\n", st->desc_why);
        set_color(COL_RESET);

        kill_goodbyedpi();
        PROCESS_INFORMATION pi = start_goodbyedpi(exePath, st->args);

        double total_time = 0.0;
        st->passed = 0;
        st->total = TARGET_COUNT;
        st->controls_ok = 1;

        for (size_t t = 0; t < TARGET_COUNT; t++) {
            probe_result_t pr = probe_target(targets[t].host, targets[t].path, targets[t].fallback_ip, 5);
            if (pr.ok) {
                st->passed++;
                total_time += pr.time_total;
                set_color(COL_GREEN);
                printf("        %-22s : %s\n", targets[t].host, pr.reason);
            } else {
                set_color(COL_RED);
                printf("        %-22s : %s\n", targets[t].host, pr.reason);
            }
            set_color(COL_RESET);
        }

        /* Check controls (must not break regular sites) */
        for (size_t c = 0; c < CONTROL_COUNT; c++) {
            probe_result_t pr = probe_target(controls[c].host, controls[c].path, controls[c].fallback_ip, 4);
            if (!pr.ok) {
                st->controls_ok = 0;
                set_color(COL_YELLOW);
                printf("        %-22s : NORMAL SITE BOZULDU (%s)\n", controls[c].host, pr.reason);
                set_color(COL_RESET);
            }
        }

        if (st->passed > 0) {
            st->avg_time = total_time / (double)st->passed;
        }

        stop_process(&pi);

        if (st->passed == st->total && st->controls_ok) {
            set_color(COL_GREEN);
            printf("        -> SONUC: %d/%d BASARILI (Ortalama Yanit: %.2fs)\n", st->passed, st->total, st->avg_time);
            set_color(COL_RESET);
            if (!best_strat) {
                best_strat = st;
            } else if (strcmp(st->id, "kyk") == 0) {
                best_strat = st; /* preferred */
            } else if (st->avg_time < best_strat->avg_time && st->avg_time > 0.05 && strcmp(best_strat->id, "kyk") != 0) {
                best_strat = st;
            }
        } else if (st->passed > 0) {
            set_color(COL_YELLOW);
            printf("        -> SONUC: %d/%d KISMEN CALISTI\n", st->passed, st->total);
            set_color(COL_RESET);
            if (!best_strat) best_strat = st;
        } else {
            set_color(COL_RED);
            printf("        -> SONUC: CALISMADI\n");
            set_color(COL_RESET);
            if (strcmp(st->id, "sni") == 0) {
                print_info("Nedeni: Yurt DPI'i stateful TCP reassembly yapiyor. Sahte paket olmadan calismaz.");
            } else if (strcmp(st->id, "ttl3") == 0) {
                print_info("Nedeni: TTL 3 mesafesi kisa kaldi; sahte paket DPI cihazina ulasamadi.");
            } else if (strcmp(st->id, "m9") == 0) {
                print_info("Nedeni: Yurt donanimi/router'i bozuk checksum'li paketleri engelliyor.");
            }
        }
        printf("\n");
    }

    /* -------------------------------------------------------------
     * 3. Sonuc ve Baslatici Olusturma
     * ------------------------------------------------------------- */
    print_title("3/3  DEGERLENDIRME VE BASLATICI");

    if (best_strat && best_strat->passed > 0) {
        set_color(COL_GREEN);
        printf("  TEBRIKLER! Yurdunuz icin calisan en optimize mod tespit edildi:\n");
        printf("  ===============================================================\n");
        printf("  Strateji : %s\n", best_strat->name);
        printf("  Parametre: goodbyedpi.exe %s\n", best_strat->args);
        printf("  Basari   : %d/%d (Ortalama Gecikme: %.2fs)\n", best_strat->passed, best_strat->total, best_strat->avg_time);
        printf("  ===============================================================\n\n");
        set_color(COL_RESET);

        /* Write KYK_BASLAT.cmd */
        char launcherPath[MAX_PATH];
        snprintf(launcherPath, sizeof(launcherPath), "%s\\KYK_BASLAT.cmd", rootDir);

        FILE *f = fopen(launcherPath, "w");
        if (f) {
            fprintf(f, "@ECHO OFF\n");
            fprintf(f, ":: kyk_test.exe tarafindan otomatik uretildi.\n");
            fprintf(f, ":: Strateji: %s\n", best_strat->name);
            fprintf(f, "chcp 65001 >nul\n");
            fprintf(f, "PUSHD \"%%~dp0\"\n");
            fprintf(f, "net session >nul 2>&1\n");
            fprintf(f, "if %%errorLevel%% neq 0 (\n");
            fprintf(f, "    echo Yonetici izni isteniyor...\n");
            fprintf(f, "    powershell -NoProfile -Command \"Start-Process -FilePath '%%~f0' -Verb RunAs\"\n");
            fprintf(f, "    exit /b\n");
            fprintf(f, ")\n");
            fprintf(f, "set _arch=x86\n");
            fprintf(f, "IF \"%%PROCESSOR_ARCHITECTURE%%\"==\"AMD64\" (set _arch=x86_64)\n");
            fprintf(f, "IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)\n");
            fprintf(f, "echo GSB/KYK GoodbyeDPI baslatiliyor: %s\n", best_strat->args);
            fprintf(f, "echo Kapatmak icin bu pencereyi kapatin.\n");
            fprintf(f, "\"%%~dp0%%_arch%%\\goodbyedpi.exe\" %s\n", best_strat->args);
            fprintf(f, "POPD\n");
            fclose(f);
            print_ok("KYK_BASLAT.cmd basariyla guncellendi.");
        }

        set_color(COL_WHITE);
        printf("\n  Ne yapmak istersiniz?\n\n");
        printf("  [1] (Onerilen) Bu modu SIMDI baslat ve GoodbyeDPI'i calisir durumda birak\n");
        printf("  [2] Windows Hizmeti (Service) olarak kur (Bilgisayar her acildiginda otomatik calissin)\n");
        printf("  [3] Sadece KYK_BASLAT.cmd dosyasini hazirla ve cik\n\n");
        set_color(COL_CYAN);
        printf("  Seciminiz [1/2/3] (Varsayilan: 1): ");
        set_color(COL_RESET);

        char ans[32] = "";
        if (fgets(ans, sizeof(ans), stdin)) {
            if (ans[0] == '2') {
                system("sc.exe stop GoodbyeDPI >nul 2>&1");
                system("sc.exe delete GoodbyeDPI >nul 2>&1");
                Sleep(500);

                char scCmd[2048];
                snprintf(scCmd, sizeof(scCmd),
                    "sc.exe create GoodbyeDPI binPath= \"\\\"%s\\\" %s\" start= auto DisplayName= \"GoodbyeDPI (GSB/KYK)\" >nul 2>&1",
                    exePath, best_strat->args);
                system(scCmd);
                system("sc.exe description GoodbyeDPI \"GSB/KYK yurt interneti icin optimize edilmis DPI atlatma servisi.\" >nul 2>&1");
                system("sc.exe start GoodbyeDPI >nul 2>&1");
                print_ok("GoodbyeDPI Windows Hizmeti olarak kuruldu ve arka planda calisiyor!");
            } else if (ans[0] == '3') {
                print_ok("KYK_BASLAT.cmd hazir. Istediginiz zaman cift tiklayarak baslatabilirsiniz.");
            } else {
                /* Option 1: Start immediately via ShellExecute */
                print_ok("GoodbyeDPI baslatiliyor...");
                ShellExecuteA(NULL, "open", launcherPath, NULL, rootDir, SW_SHOW);
                print_ok("GoodbyeDPI aktif edildi! Discord ve diger siteleri kullanabilirsiniz.");
            }
        }
    } else {
        print_bad("Hicbir strateji engeli tam olarak asamadi.");
        print_info("Yurdunuzda IP bazli engelleme veya derin port blokaji olabilir.");
    }

    printf("\nIslem tamamlandi. Cikmak icin ENTER tusuna basin...");
    getchar();
    return 0;
}
