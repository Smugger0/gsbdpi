@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK / TTNET DISCORD BASLATICI (MOD 1 - ONERILEN)
echo ===================================================================
echo.
echo [1] Mod 1: -5 --set-ttl 5 parametresiyle DPI atlatma aktif.
echo [2] Yurt giris portali (wifi.gsb.gov.tr) ve e-devlet etkilenmez.
echo [3] Seffaf DoH aktif: Discord ve diger sitelerin DNS'i guvenle cozulur.
echo [4] Yalnizca blacklist_kyk.txt icerisindeki engelli sitelere uygulanir.
echo.
echo Kapatmak icin bu pencereyi veya GoodbyeDPI penceresini kapatabilirsiniz.
echo.

start "" "%~sdp0%_arch%\goodbyedpi.exe" -5 --set-ttl 5 -q --doh --max-payload 1200 --blacklist "%~sdp0blacklist_kyk.txt"

POPD
