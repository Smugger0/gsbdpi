@ECHO OFF
chcp 65001 >nul
SETLOCAL EnableDelayedExpansion

echo ===================================================================
echo   DISCORD HOSTS GUNCELLEYICI (UPDATE FAILED KESIN COZUMU)
echo ===================================================================
echo.
echo Bu arac, Windows'un Discord sunucularini ISS/KYK tarafindan engellenen
echo sahte IP (195.175.254.2) yerine gercek Cloudflare IP'sine baglamasini saglar.
echo.

:: Yonetici kontrolu
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [HATA] Bu dosyayi SAG TIKLAYIP "YONETICI OLARAK CALISTIR" demelisiniz!
    echo.
    pause
    exit /b 1
)

set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"

:: Once eski eklenmis Discord kayitlarini temizleyelim
powershell -NoProfile -Command "$content = Get-Content '%HOSTS_FILE%' -Raw -ErrorAction SilentlyContinue; if ($content) { $newContent = $content -replace '(?s)# --- DISCORD KYK / DPI DUZELTME BASLANGIC ---.*?# --- DISCORD KYK / DPI DUZELTME BITIS ---[\r\n]*', ''; [System.IO.File]::WriteAllText('%HOSTS_FILE%', $newContent, [System.Text.Encoding]::UTF8) }"

:: Yeni kayitlari ekleyelim
powershell -NoProfile -Command "$discordBlock = @'

# --- DISCORD KYK / DPI DUZELTME BASLANGIC ---
162.159.138.232 discord.com
162.159.138.232 updates.discord.com
162.159.138.232 gateway.discord.gg
162.159.138.232 cdn.discordapp.com
162.159.138.232 media.discordapp.net
162.159.138.232 router.discordapp.net
162.159.138.232 dl.discordapp.net
162.159.138.232 status.discordapp.com
162.159.138.232 support.discord.com
162.159.138.232 discordapp.com
162.159.138.232 discord.gg
162.159.138.232 discordapp.net
162.159.138.232 discord.media
# --- DISCORD KYK / DPI DUZELTME BITIS ---
'@; Add-Content -Path '%HOSTS_FILE%' -Value $discordBlock -Encoding UTF8"

:: DNS onbellegini temizle
ipconfig /flushdns >nul

echo [BASARILI] Discord alan adlari gercek Cloudflare IP'lerine yonlendirildi!
echo [BASARILI] DNS onbellegi temizlendi.
echo.
echo Artik GoodbyeDPI calisirken Discord'u actiginizda "Update Failed" hatasi almayacaksiniz.
echo.
pause
