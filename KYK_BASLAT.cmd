@ECHO OFF
:: kyk_test.exe tarafindan otomatik uretildi.
:: Strateji: Yeni KYK Modu (Reverse-Frag + TTL 5 + DoH + Beyaz Liste)
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
echo GSB/KYK GoodbyeDPI baslatiliyor: --kyk
echo Kapatmak icin bu pencereyi kapatin.
"%~dp0%_arch%\goodbyedpi.exe" --kyk
POPD
