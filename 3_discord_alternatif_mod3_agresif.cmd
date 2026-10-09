@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK DISCORD BASLATICI (MOD 3 - AGRESIF -9 MODU)
echo ===================================================================
echo.
echo * Mod 3: -9 (wrong-seq + wrong-chksum) parametresiyle DPI atlatma aktif.
echo.

start "" "%~sdp0%_arch%\goodbyedpi.exe" -9 --blacklist "%~sdp0blacklist_kyk.txt"

POPD
