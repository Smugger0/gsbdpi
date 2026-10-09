@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK YURT INTERNETI ICIN GOODBYEDPI (YENI KYK MODU)
echo ===================================================================
echo.
echo [1] KYK Modu aktif: Mod -5 (TTL 5 Fake Packet) + Ters Parçalama.
echo [2] Seffaf DoH aktif: Sistem DNS sorgulari HTTPS uzerinden guvenle cozulur.
echo     (Hosts dosyasini degistirmeden Discord guncellemeleri acilir!)
echo [3] wifi.gsb.gov.tr, e-Devlet ve universite siteleri beyaz listededir.
echo [4] QUIC engelleme devrede (Discord ses ve gorusme baglantisi stabildir).
echo.
echo NOT: Kapatmak icin bu pencereyi veya GoodbyeDPI penceresini kapatin.
echo ===================================================================
echo.

start "" "%~sdp0%_arch%\goodbyedpi.exe" --kyk --blacklist "%~sdp0blacklist_kyk.txt"

POPD
