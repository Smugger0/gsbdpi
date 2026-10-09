#Requires -Version 5.1
<#
.SYNOPSIS
    GSB / KYK yurt interneti icin GoodbyeDPI strateji test araci (CLI).

.DESCRIPTION
    1) Ag analizi   : DNS zehirleme var mi, DoH erisilebilir mi, SNI engeli var mi?
    2) DPI testleri : Her GoodbyeDPI stratejisini sirayla calistirir, engelli
                      sitelere gercekten baglanilabiliyor mu olcer.
    3) DNS testleri : DNS cozumu icin --doh ve eski --dns-addr yontemlerini dener.
    4) Sonuc        : Calisan en guvenli stratejiyi onerir, KYK_BASLAT.cmd uretir,
                      istenirse Windows servisi olarak kurar.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File kyk_test.ps1
    powershell -ExecutionPolicy Bypass -File kyk_test.ps1 -Quick
    powershell -ExecutionPolicy Bypass -File kyk_test.ps1 -Yes -ReportJson sonuc.json
#>
[CmdletBinding()]
param(
    [string]$Exe = "",
    [switch]$Quick,          # Tam basarili ilk stratejide dur
    [switch]$Yes,            # Soru sorma (varsayilanlari kabul et)
    [switch]$NoGenerate,     # KYK_BASLAT.cmd uretme
    [switch]$InstallService, # Sonucta servis kur (sormadan)
    [int]$Timeout = 6,
    [string[]]$Only,         # Sadece verilen strateji Id'lerini test et
    [string]$ReportJson = ""
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkDir = Join-Path $env:TEMP "gsbdpi_test"
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

# --------------------------------------------------------------------------
# Test hedefleri
# --------------------------------------------------------------------------
# Turkiye'de SNI/DNS ile engellenen siteler (Discord oncelikli)
$Targets = @(
    @{ Host = 'discord.com';         Path = '/';            Fallback = '162.159.138.232' },
    @{ Host = 'gateway.discord.gg';  Path = '/';            Fallback = '162.159.135.234' },
    @{ Host = 'cdn.discordapp.com';  Path = '/';            Fallback = '162.159.129.233' },
    @{ Host = 'updates.discord.com'; Path = '/';            Fallback = '162.159.138.232' },
    @{ Host = 'pastebin.com';        Path = '/';            Fallback = '172.66.40.172'   },
    @{ Host = 'www.roblox.com';      Path = '/';            Fallback = '128.116.21.4'    }
)
# Engelli olmayan kontrol siteleri: strateji normal siteleri bozuyor mu?
$Controls = @(
    @{ Host = 'www.cloudflare.com';  Path = '/';            Fallback = '104.16.123.96'   },
    @{ Host = 'www.google.com';      Path = '/generate_204'; Fallback = '142.250.187.100' }
)

# Turk ISS / GSB sahte (engel) IP'leri
$KnownBlockIPs = @('195.175.254.2', '2a01:358:4014:a00::3', '0.0.0.0', '127.0.0.1', '::')

# --------------------------------------------------------------------------
# Strateji listesi: GUVENLIDEN RISKLIYE dogru siralidir.
#   Custom = sadece bu projedeki yamali goodbyedpi.exe ile calisir
#   Safe   = sahte paket gondermez, normal siteleri bozma riski yok
# --------------------------------------------------------------------------
$Strategies = @(
    @{ Id = 'kyk';      Custom = $true;  Safe = $true;  Name = 'KYK modu (SNI icinden bol, sirali)';        Args = '--kyk --no-doh' },
    @{ Id = 'kyk1';     Custom = $true;  Safe = $true;  Name = 'KYK modu, SNI ofset 1';                     Args = '--kyk --no-doh --sni-split-offset 1' },
    @{ Id = 'kyk5';     Custom = $true;  Safe = $true;  Name = 'KYK modu, SNI ofset 5';                     Args = '--kyk --no-doh --sni-split-offset 5' },
    @{ Id = 'sni';      Custom = $false; Safe = $true;  Name = 'SNI oncesinden bol (--frag-by-sni)';        Args = '-q --native-frag -f 2 -e 2 --frag-by-sni' },
    @{ Id = 'e1';       Custom = $false; Safe = $true;  Name = 'ClientHello 1. bayttan bol';                Args = '-q --native-frag -f 1 -e 1' },
    @{ Id = 'rev2';     Custom = $false; Safe = $true;  Name = 'Ters sirali bolme (-e 2 --reverse-frag)';   Args = '-q --reverse-frag -f 2 -e 2' },
    @{ Id = 'm1';       Custom = $false; Safe = $true;  Name = 'Eski mod -1 (pencere boyutu)';              Args = '-1 -q' },
    @{ Id = 'm5';       Custom = $false; Safe = $false; Name = 'Mod -5 (auto-ttl sahte paket)';             Args = '-5 -q' },
    @{ Id = 'm5ttl5';   Custom = $false; Safe = $false; Name = 'Mod -5 + TTL 5 (GoodbyeDPI-Turkey)';        Args = '-5 --set-ttl 5 -q' },
    @{ Id = 'ttl3';     Custom = $false; Safe = $false; Name = 'Sahte paket TTL 3';                         Args = '-q --reverse-frag -f 2 -e 2 --set-ttl 3' },
    @{ Id = 'm6';       Custom = $false; Safe = $false; Name = 'Mod -6 (wrong-seq)';                        Args = '-6 -q' },
    @{ Id = 'm7';       Custom = $false; Safe = $false; Name = 'Mod -7 (wrong-chksum)';                     Args = '-7 -q' },
    @{ Id = 'm9';       Custom = $false; Safe = $false; Name = 'Mod -9 (wrong-seq + wrong-chksum)';         Args = '-9' },
    @{ Id = 'fakesni';  Custom = $false; Safe = $false; Name = 'Sahte SNI (www.google.com) + -9';           Args = '-9 --fake-with-sni www.google.com' },
    @{ Id = 'fakegen';  Custom = $false; Safe = $false; Name = 'Rastgele sahte paket x5 + -9';              Args = '-9 --fake-gen 5 --fake-resend 2' }
)

# DNS yontemleri (DNS zehirleniyorsa denenir)
$DnsMethods = @(
    @{ Id = 'doh';       Custom = $true;  Name = 'DoH (HTTPS uzerinden DNS, 1.1.1.1/8.8.8.8)'; Args = '--doh' },
    @{ Id = 'yandex';    Custom = $false; Name = 'Yandex DNS 77.88.8.8:1253';                   Args = '--dns-addr 77.88.8.8 --dns-port 1253' },
    @{ Id = 'adguard';   Custom = $false; Name = 'AdGuard DNS 94.140.14.14:5353';               Args = '--dns-addr 94.140.14.14 --dns-port 5353' },
    @{ Id = 'opendns';   Custom = $false; Name = 'OpenDNS 208.67.222.222:5353';                 Args = '--dns-addr 208.67.222.222 --dns-port 5353' }
)

# --------------------------------------------------------------------------
# Yardimci fonksiyonlar
# --------------------------------------------------------------------------
function Write-Title($text) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
    Write-Host ("  " + $text) -ForegroundColor Cyan
    Write-Host ("=" * 70) -ForegroundColor DarkCyan
}
function Write-Ok($text)   { Write-Host "  [ OK ] $text" -ForegroundColor Green }
function Write-Bad($text)  { Write-Host "  [HATA] $text" -ForegroundColor Red }
function Write-Warn2($text){ Write-Host "  [UYARI] $text" -ForegroundColor Yellow }
function Write-Info($text) { Write-Host "  [BILGI] $text" -ForegroundColor Gray }

function Ask-YesNo($question, $default = $true) {
    if ($Yes) { return $default }
    $suffix = if ($default) { "[E/h]" } else { "[e/H]" }
    $ans = Read-Host "  $question $suffix"
    if ([string]::IsNullOrWhiteSpace($ans)) { return $default }
    return ($ans.Trim().ToLower() -in @('e', 'evet', 'y', 'yes'))
}

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Stop-GoodbyeDPI {
    Get-Process -Name goodbyedpi -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Kill(); $_.WaitForExit(3000) | Out-Null } catch {}
    }
}

# DoH ile gercek IP adreslerini ogren (curl, 1.1.1.1 ve 8.8.8.8 IP uzerinden)
function Resolve-DoH([string]$name) {
    $urls = @(
        "https://1.1.1.1/dns-query?name=$name&type=A",
        "https://8.8.8.8/resolve?name=$name&type=A"
    )
    foreach ($u in $urls) {
        try {
            $json = & curl.exe -s -m 5 -H "accept: application/dns-json" $u 2>$null
            if ($LASTEXITCODE -eq 0 -and $json) {
                $obj = $json | ConvertFrom-Json
                $ips = @($obj.Answer | Where-Object { $_.type -eq 1 } | ForEach-Object { $_.data })
                if ($ips.Count -gt 0) { return $ips }
            }
        } catch {}
    }
    return @()
}

function Resolve-System([string]$name) {
    try {
        $r = Resolve-DnsName -Name $name -Type A -DnsOnly -NoHostsFile -ErrorAction Stop -QuickTimeout
        return @($r | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.IPAddress })
    } catch { return @() }
}

function Test-Poisoned($systemIps, $dohIps) {
    if ($systemIps.Count -eq 0) { return $true }
    foreach ($ip in $systemIps) { if ($KnownBlockIPs -contains $ip) { return $true } }
    if ($dohIps.Count -eq 0) { return $false }
    # Ayni /16 blogunda hic ortak adres yoksa supheli kabul et
    $p1 = $systemIps | ForEach-Object { ($_ -split '\.')[0..1] -join '.' }
    $p2 = $dohIps    | ForEach-Object { ($_ -split '\.')[0..1] -join '.' }
    return -not ($p1 | Where-Object { $p2 -contains $_ })
}

# Tek bir HTTPS istegi. $ip verilirse DNS atlanir (--resolve).
function Invoke-Probe($target, [string]$ip, [int]$port = 443) {
    $scheme = if ($port -eq 80) { 'http' } else { 'https' }
    $url = "{0}://{1}{2}" -f $scheme, $target.Host, $target.Path
    $curlArgs = @('-s', '-o', 'NUL', '-m', "$Timeout", '--connect-timeout', '4',
                  '-A', 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) GSBDPI-Test',
                  '-w', '%{http_code} %{time_appconnect} %{time_total}')
    if ($ip) { $curlArgs += @('--resolve', ("{0}:{1}:{2}" -f $target.Host, $port, $ip)) }
    $curlArgs += $url
    $out = & curl.exe @curlArgs 2>$null
    $code = $LASTEXITCODE
    $parts = "$out".Trim() -split ' '
    $http = if ($parts.Count -ge 1) { $parts[0] } else { '000' }
    $ok = ($code -eq 0 -and $http -ne '000')
    $reason = switch ($code) {
        0  { "HTTP $http" }
        6  { 'DNS cozulemedi' }
        7  { 'Baglanti kurulamadi' }
        28 { 'Zaman asimi' }
        35 { 'TLS sifirlandi (DPI engeli)' }
        52 { 'Bos yanit' }
        56 { 'Baglanti sifirlandi (DPI engeli)' }
        60 { 'Sertifika hatasi (sahte sayfa)' }
        default { "curl hata $code" }
    }
    $t = 0.0
    if ($parts.Count -ge 3) { [double]::TryParse($parts[2], [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$t) | Out-Null }
    return [pscustomobject]@{ Host = $target.Host; Ok = $ok; Code = $code; Http = $http; Reason = $reason; Time = $t }
}

function Start-GDPI([string]$argString, [string]$tag) {
    Stop-GoodbyeDPI
    $log = Join-Path $WorkDir "gdpi_$tag.log"
    $err = Join-Path $WorkDir "gdpi_$tag.err"
    Remove-Item $log, $err -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $script:ExePath -ArgumentList $argString -WindowStyle Hidden `
            -RedirectStandardOutput $log -RedirectStandardError $err -PassThru
    # "Filter activated" mesajini bekle (yamali surum ciktiyi tamponlamaz)
    $deadline = (Get-Date).AddSeconds(8)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 250
        $txt = Get-Content $log -Raw -ErrorAction SilentlyContinue
        if ($txt -match 'Filter activated') { Start-Sleep -Milliseconds 400; return $p }
        if ($txt -match 'Error opening filter|ERROR|error!') { break }
        if ($p.HasExited) { break }
    }
    if (-not $p.HasExited -and -not $script:UnbufferedOutput) {
        # Resmi surum: cikti tamponlu, sadece calisiyor mu bak
        Start-Sleep -Milliseconds 500
        if (-not $p.HasExited) { return $p }
    }
    $txt = Get-Content $log -Raw -ErrorAction SilentlyContinue
    try { if (-not $p.HasExited) { $p.Kill() } } catch {}
    throw "GoodbyeDPI baslatilamadi ($argString). Cikti: $txt"
}

# --------------------------------------------------------------------------
# 0) On kontroller
# --------------------------------------------------------------------------
Clear-Host
Write-Host ""
Write-Host "  GSB / KYK GoodbyeDPI Strateji Test Araci" -ForegroundColor Cyan
Write-Host "  Yurt internetinde hangi yontemin calistigini otomatik bulur." -ForegroundColor Gray

if (-not (Test-Admin)) {
    Write-Bad "Bu arac YONETICI olarak calistirilmalidir (WinDivert surucusu icin)."
    Write-Info "KYK_TEST.cmd dosyasina sag tiklayip 'Yonetici olarak calistir' secin."
    exit 1
}
if (-not (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    Write-Bad "curl.exe bulunamadi. Windows 10 1803 veya daha yeni bir surum gerekir."
    exit 1
}

if (-not $Exe) {
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'x86_64' } else { 'x86' }
    $Exe = Join-Path $Root "$arch\goodbyedpi.exe"
}
if (-not (Test-Path $Exe)) { Write-Bad "goodbyedpi.exe bulunamadi: $Exe"; exit 1 }
$script:ExePath = (Resolve-Path $Exe).Path

# Calisan GoodbyeDPI / servis var mi?
$svc = Get-Service -Name GoodbyeDPI -ErrorAction SilentlyContinue
$svcWasRunning = $false
if ($svc -and $svc.Status -eq 'Running') {
    Write-Warn2 "GoodbyeDPI servisi calisiyor; test icin gecici olarak durdurulacak."
    Stop-Service GoodbyeDPI -Force
    $svcWasRunning = $true
}
if (Get-Process -Name goodbyedpi -ErrorAction SilentlyContinue) {
    Write-Warn2 "Calisan goodbyedpi.exe kapatiliyor."
    Stop-GoodbyeDPI
}

# Yamali (KYK) surum mu?
$helpText = (& $script:ExePath --kyk-help-probe 2>&1 | Out-String)
$script:CustomBuild = ($helpText -match '--kyk') -and ($helpText -match '--doh')
$script:UnbufferedOutput = $script:CustomBuild
$verLine = ($helpText -split "`n" | Where-Object { $_ -match 'GoodbyeDPI' } | Select-Object -First 1)
Write-Info ("Surum: " + "$verLine".Trim())
if ($script:CustomBuild) { Write-Ok "Yamali GSB/KYK surumu tespit edildi (--kyk, --doh destekli)." }
else { Write-Warn2 "Resmi GoodbyeDPI surumu: --kyk ve --doh testleri atlanacak." }

$report = [ordered]@{
    Date        = (Get-Date).ToString('s')
    Computer    = $env:COMPUTERNAME
    Os          = (Get-CimInstance Win32_OperatingSystem).Caption
    Exe         = $script:ExePath
    CustomBuild = $script:CustomBuild
    Network     = $null
    Dpi         = @()
    Dns         = @()
    Best        = $null
}

try {
# --------------------------------------------------------------------------
# 1) Ag analizi
# --------------------------------------------------------------------------
Write-Title "1/4  AG ANALIZI"
$dnsServers = @(Get-DnsClientServerAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.ServerAddresses } | ForEach-Object { "$($_.InterfaceAlias): $($_.ServerAddresses -join ', ')" })
foreach ($d in $dnsServers) { Write-Info "DNS sunucusu -> $d" }

Clear-DnsClientCache -ErrorAction SilentlyContinue

# DNS gaspi (hijack) testi: var olmayan bir DNS sunucusuna soru sor
$hijack = $false
try {
    $r = Resolve-DnsName -Name 'example.com' -Type A -Server '192.0.2.1' -DnsOnly -QuickTimeout -ErrorAction Stop
    if ($r) { $hijack = $true }
} catch {}
if ($hijack) { Write-Warn2 "Ag TUM DNS trafigini gaspediyor (var olmayan sunucu bile cevap verdi). --dns-addr ise yaramaz." }
else { Write-Info "DNS gaspi tespit edilmedi." }

$dohOk = (Resolve-DoH 'example.com').Count -gt 0
if ($dohOk) { Write-Ok "DoH (1.1.1.1 / 8.8.8.8 HTTPS) erisilebilir." } else { Write-Bad "DoH erisilemiyor." }

$poisonedCount = 0
foreach ($t in ($Targets + $Controls)) {
    $sys = Resolve-System $t.Host
    $doh = if ($dohOk) { Resolve-DoH $t.Host } else { @() }
    $t.SystemIps = $sys
    $t.RealIp = if ($doh.Count -gt 0) { $doh[0] } else { $t.Fallback }
    $t.Poisoned = Test-Poisoned $sys $doh
    $isTarget = $Targets -contains $t
    if ($t.Poisoned -and $isTarget) { $poisonedCount++ }
    $sysTxt = if ($sys.Count) { $sys[0] } else { '(yok)' }
    $line = "{0,-22} sistem DNS: {1,-16} gercek: {2}" -f $t.Host, $sysTxt, $t.RealIp
    if ($t.Poisoned) { Write-Bad "$line  <- ZEHIRLI" } else { Write-Info $line }
}

Write-Host ""
Write-Info "Engelsiz baglanti testi (gercek IP ile, GoodbyeDPI KAPALI):"
$baseline = @()
foreach ($t in ($Targets + $Controls)) {
    $res = Invoke-Probe $t $t.RealIp
    $baseline += $res
    if ($res.Ok) { Write-Ok ("{0,-22} {1}" -f $t.Host, $res.Reason) }
    else { Write-Bad ("{0,-22} {1}" -f $t.Host, $res.Reason) }
}
$blockedHosts = @($baseline | Where-Object { -not $_.Ok -and ($Targets.Host -contains $_.Host) } | ForEach-Object { $_.Host })
$controlsBroken = @($baseline | Where-Object { -not $_.Ok -and ($Controls.Host -contains $_.Host) })

$report.Network = [ordered]@{
    DnsServers = $dnsServers; DnsHijack = $hijack; DohReachable = $dohOk
    PoisonedTargets = $poisonedCount; SniBlocked = $blockedHosts
}

if ($controlsBroken.Count -gt 0) {
    Write-Warn2 "Kontrol siteleri bile acilmiyor: internet baglantinizi / yurt girisini (wifi.gsb.gov.tr) kontrol edin."
}
if ($blockedHosts.Count -eq 0) {
    Write-Ok "Bu agda SNI/DPI engeli tespit edilmedi. Sadece DNS cozumu gerekebilir."
}
else {
    Write-Warn2 ("DPI (SNI) engeli olan siteler: " + ($blockedHosts -join ', '))
}

# --------------------------------------------------------------------------
# 2) DPI strateji testleri
# --------------------------------------------------------------------------
Write-Title "2/4  DPI ATLATMA STRATEJILERI TEST EDILIYOR"
$testTargets = @($Targets | Where-Object { $blockedHosts -contains $_.Host })
if ($testTargets.Count -eq 0) { $testTargets = @($Targets | Select-Object -First 2) }

$list = $Strategies
if ($Only) { $list = @($Strategies | Where-Object { $Only -contains $_.Id }) }
$i = 0
foreach ($s in $list) {
    $i++
    if ($s.Custom -and -not $script:CustomBuild) { continue }
    Write-Host ""
    Write-Host ("  [{0}/{1}] {2}" -f $i, $list.Count, $s.Name) -ForegroundColor White
    Write-Host ("        goodbyedpi.exe {0}" -f $s.Args) -ForegroundColor DarkGray
    $entry = [ordered]@{ Id = $s.Id; Name = $s.Name; Args = $s.Args; Safe = $s.Safe; Passed = 0; Total = 0; ControlsOk = $true; AvgTime = 0; Details = @(); Error = $null }
    try {
        $proc = Start-GDPI $s.Args $s.Id
        $times = @()
        foreach ($t in $testTargets) {
            $res = Invoke-Probe $t $t.RealIp
            $entry.Total++
            if ($res.Ok) { $entry.Passed++; $times += $res.Time }
            $entry.Details += "$($t.Host): $($res.Reason)"
            $color = if ($res.Ok) { 'Green' } else { 'Red' }
            Write-Host ("        {0,-22} {1}" -f $t.Host, $res.Reason) -ForegroundColor $color
        }
        foreach ($c in $Controls) {
            $res = Invoke-Probe $c $c.RealIp
            if (-not $res.Ok) {
                $entry.ControlsOk = $false
                Write-Host ("        {0,-22} {1}  (KONTROL SITESI BOZULDU)" -f $c.Host, $res.Reason) -ForegroundColor Yellow
            }
        }
        if ($times.Count) { $entry.AvgTime = [math]::Round((($times | Measure-Object -Average).Average), 2) }
    }
    catch {
        $entry.Error = $_.Exception.Message
        Write-Bad $entry.Error
    }
    finally { Stop-GoodbyeDPI }

    $sum = "{0}/{1} basarili" -f $entry.Passed, $entry.Total
    if ($entry.Total -gt 0 -and $entry.Passed -eq $entry.Total -and $entry.ControlsOk) { Write-Ok "SONUC: $sum" }
    elseif ($entry.Passed -gt 0) { Write-Warn2 "SONUC: $sum" }
    else { Write-Bad "SONUC: $sum" }
    $report.Dpi += [pscustomobject]$entry

    if ($Quick -and $entry.Total -gt 0 -and $entry.Passed -eq $entry.Total -and $entry.ControlsOk) {
        Write-Info "-Quick: ilk tam basarili strateji bulundu, digerleri atlaniyor."
        break
    }
}

$working = @($report.Dpi | Where-Object { $_.Total -gt 0 -and $_.Passed -eq $_.Total -and $_.ControlsOk })
$best = $working | Select-Object -First 1   # liste guvenliden riskliye sirali
if (-not $best) {
    $best = $report.Dpi | Where-Object { $_.ControlsOk } | Sort-Object -Property Passed -Descending | Select-Object -First 1
}

# --------------------------------------------------------------------------
# 3) DNS testleri
# --------------------------------------------------------------------------
Write-Title "3/4  DNS COZUMU TEST EDILIYOR"
$bestDns = $null
$needDns = ($poisonedCount -gt 0)
if (-not $needDns) {
    Write-Ok "DNS zehirlenmesi yok, DNS yontemi gerekmiyor."
}
elseif (-not $best -or $best.Passed -eq 0) {
    Write-Warn2 "Calisan DPI stratejisi olmadigindan DNS testi atlandi."
}
else {
    foreach ($m in $DnsMethods) {
        if ($m.Custom -and -not $script:CustomBuild) { continue }
        Write-Host ""
        Write-Host ("  {0}" -f $m.Name) -ForegroundColor White
        $argString = "{0} {1}" -f $best.Args, $m.Args
        $argString = $argString -replace '--no-doh\s*', ''
        Write-Host ("        goodbyedpi.exe {0}" -f $argString) -ForegroundColor DarkGray
        $entry = [ordered]@{ Id = $m.Id; Name = $m.Name; Args = $m.Args; Resolved = 0; Connected = 0; Total = 0; Error = $null }
        try {
            $proc = Start-GDPI $argString ("dns_" + $m.Id)
            Clear-DnsClientCache -ErrorAction SilentlyContinue
            Start-Sleep -Milliseconds 300
            foreach ($t in $Targets) {
                $entry.Total++
                $sys = Resolve-System $t.Host
                $clean = ($sys.Count -gt 0) -and -not (Test-Poisoned $sys @($t.RealIp))
                if ($clean) { $entry.Resolved++ }
                # Uctan uca: sistem DNS'i ile (--resolve OLMADAN) baglan
                $res = Invoke-Probe $t $null
                if ($res.Ok) { $entry.Connected++ }
                $ipTxt = if ($sys.Count) { $sys[0] } else { '(yok)' }
                $color = if ($clean -and $res.Ok) { 'Green' } elseif ($clean -or $res.Ok) { 'Yellow' } else { 'Red' }
                Write-Host ("        {0,-22} DNS: {1,-16} baglanti: {2}" -f $t.Host, $ipTxt, $res.Reason) -ForegroundColor $color
            }
        }
        catch { $entry.Error = $_.Exception.Message; Write-Bad $entry.Error }
        finally { Stop-GoodbyeDPI; Clear-DnsClientCache -ErrorAction SilentlyContinue }
        $report.Dns += [pscustomobject]$entry
        if ($entry.Total -gt 0 -and $entry.Resolved -eq $entry.Total -and $entry.Connected -eq $entry.Total) {
            Write-Ok ("SONUC: {0}/{1} DNS dogru, {2}/{1} baglanti basarili" -f $entry.Resolved, $entry.Total, $entry.Connected)
            if (-not $bestDns) { $bestDns = $entry }
            if ($Quick) { break }
        }
        else {
            Write-Bad ("SONUC: {0}/{1} DNS dogru, {2}/{1} baglanti basarili" -f $entry.Resolved, $entry.Total, $entry.Connected)
        }
    }
}

# --------------------------------------------------------------------------
# 4) Sonuc ve oneriler
# --------------------------------------------------------------------------
Write-Title "4/4  SONUC"
Write-Host ""
Write-Host ("  {0,-10} {1,-44} {2,-8} {3}" -f 'ID', 'STRATEJI', 'SONUC', 'NOT') -ForegroundColor Cyan
foreach ($e in $report.Dpi) {
    $note = @()
    if (-not $e.Safe) { $note += 'sahte paket' }
    if (-not $e.ControlsOk) { $note += 'normal siteleri bozuyor' }
    if ($e.Error) { $note += 'baslatilamadi' }
    $color = if ($e.Total -gt 0 -and $e.Passed -eq $e.Total -and $e.ControlsOk) { 'Green' } elseif ($e.Passed -gt 0) { 'Yellow' } else { 'DarkGray' }
    Write-Host ("  {0,-10} {1,-44} {2,-8} {3}" -f $e.Id, $e.Name, ("{0}/{1}" -f $e.Passed, $e.Total), ($note -join ', ')) -ForegroundColor $color
}
Write-Host ""

$finalArgs = $null
if ($best -and $best.Passed -gt 0) {
    $finalArgs = $best.Args -replace '\s*--no-doh', ''
    if ($needDns) {
        if ($bestDns) { $finalArgs = "$finalArgs $($bestDns.Args)" }
        elseif ($script:CustomBuild -and $dohOk) { $finalArgs = "$finalArgs --doh" }
    }
    elseif ($script:CustomBuild) {
        if ($finalArgs -match '--kyk') { $finalArgs = "$finalArgs --no-doh" }
    }
    $finalArgs = ($finalArgs -replace '\s+', ' ').Trim()
    Write-Ok ("ONERILEN STRATEJI : {0}" -f $best.Name)
    if ($bestDns) { Write-Ok ("ONERILEN DNS      : {0}" -f $bestDns.Name) }
    elseif ($needDns) { Write-Warn2 "Calisan DNS yontemi bulunamadi: tarayicida DoH acin veya discord_hosts_guncelle.cmd kullanin." }
    Write-Host ""
    Write-Host "  Komut: goodbyedpi.exe $finalArgs" -ForegroundColor White
    $report.Best = [ordered]@{ Strategy = $best.Id; Dns = $(if ($bestDns) { $bestDns.Id } else { $null }); Args = $finalArgs }
}
else {
    Write-Bad "Hicbir strateji engeli tam olarak asamadi."
    Write-Info "Bu durumda GoodbyeDPI yetersiz kalir; Cloudflare WARP veya bir VPN deneyin."
}

# KYK_BASLAT.cmd uret
if ($finalArgs -and -not $NoGenerate) {
    $launcher = Join-Path $Root 'KYK_BASLAT.cmd'
    $content = @"
@ECHO OFF
:: Bu dosya kyk_test.ps1 tarafindan $(Get-Date -Format 'yyyy-MM-dd HH:mm') tarihinde otomatik uretildi.
:: Strateji: $($best.Name)
chcp 65001 >nul
PUSHD "%~dp0"
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo Yonetici izni isteniyor...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)
set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)
echo GSB/KYK GoodbyeDPI baslatiliyor: $finalArgs
echo Kapatmak icin bu pencereyi kapatin.
"%~dp0%_arch%\goodbyedpi.exe" $finalArgs
POPD
"@
    Set-Content -Path $launcher -Value $content -Encoding ASCII
    Write-Ok "KYK_BASLAT.cmd olusturuldu (cift tiklayarak baslatabilirsiniz)."

    $doService = $InstallService -or (Ask-YesNo "Bilgisayar acildiginda otomatik baslamasi icin Windows servisi olarak kurulsun mu?" $false)
    if ($doService) {
        & sc.exe stop GoodbyeDPI 2>$null | Out-Null
        & sc.exe delete GoodbyeDPI 2>$null | Out-Null
        Start-Sleep -Milliseconds 500
        $bin = "`"$script:ExePath`" $finalArgs"
        & sc.exe create GoodbyeDPI binPath= $bin start= auto DisplayName= "GoodbyeDPI (GSB/KYK)" | Out-Null
        & sc.exe description GoodbyeDPI "GSB/KYK yurt interneti icin DPI atlatma ($($best.Id))" | Out-Null
        & sc.exe start GoodbyeDPI | Out-Null
        $svcWasRunning = $false
        Write-Ok "GoodbyeDPI servisi kuruldu ve baslatildi."
    }
}
}
finally {
    Stop-GoodbyeDPI
    if ($svcWasRunning) { Start-Service GoodbyeDPI -ErrorAction SilentlyContinue }
    if ($ReportJson) {
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $ReportJson -Encoding UTF8
        Write-Info "Rapor kaydedildi: $ReportJson"
    }
    $txtReport = Join-Path $Root 'kyk_test_sonuc.json'
    $report | ConvertTo-Json -Depth 6 | Set-Content -Path $txtReport -Encoding UTF8
}
Write-Host ""
