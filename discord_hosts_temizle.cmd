@ECHO OFF
chcp 65001 >nul

echo ===================================================================
echo   DISCORD HOSTS TEMIZLEYICI
echo ===================================================================
echo.

net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [HATA] Bu dosyayi SAG TIKLAYIP "YONETICI OLARAK CALISTIR" demelisiniz!
    echo.
    pause
    exit /b 1
)

set "HOSTS_FILE=%SystemRoot%\System32\drivers\etc\hosts"

powershell -NoProfile -Command "$content = Get-Content '%HOSTS_FILE%' -Raw -ErrorAction SilentlyContinue; if ($content) { $newContent = $content -replace '(?s)# --- DISCORD KYK / DPI DUZELTME BASLANGIC ---.*?# --- DISCORD KYK / DPI DUZELTME BITIS ---[\r\n]*', ''; [System.IO.File]::WriteAllText('%HOSTS_FILE%', $newContent, [System.Text.Encoding]::UTF8) }"

ipconfig /flushdns >nul

echo [BASARILI] Hosts dosyasindaki Discord kayitlari kaldirildi.
echo [BASARILI] DNS onbellegi temizlendi.
echo.
pause
