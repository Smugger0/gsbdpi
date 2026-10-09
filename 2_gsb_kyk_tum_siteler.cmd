@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK YURT INTERNETI ICIN GOODBYEDPI (GENEL MOD - TUM SITELER)
echo ===================================================================
echo.
echo [1] Tum engelli HTTPS siteleri icin DPI atlatma aktif.
echo [2] QUIC (UDP 443) engellenerek standart TCP/TLS zorlandi.
echo.
echo NOT: Bu pencereyi kapatirsaniz GoodbyeDPI sonlandirilir.
echo.

start "" "%~sdp0%_arch%\goodbyedpi.exe" -5 --set-ttl 5 -q --max-payload 1200

POPD
