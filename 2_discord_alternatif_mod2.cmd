@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK DISCORD BASLATICI (MOD 2 - ALTERNATIF TTL 3)
echo ===================================================================
echo.
echo * Mod 2: --set-ttl 3 parametresiyle DPI atlatma aktif.
echo * Mod 1 ile baglanti saglanamazsa bu modu deneyin.
echo.

start "" "%~sdp0%_arch%\goodbyedpi.exe" --set-ttl 3 -q --max-payload 1200 --blacklist "%~sdp0blacklist_kyk.txt"

POPD
