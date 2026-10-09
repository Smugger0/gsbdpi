@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

set _arch=x86
IF "%PROCESSOR_ARCHITECTURE%"=="AMD64" (set _arch=x86_64)
IF DEFINED PROCESSOR_ARCHITEW6432 (set _arch=x86_64)

echo ===================================================================
echo   GSB / KYK YURT INTERNETI ICIN GOODBYEDPI SERVIS KURULUMU
echo ===================================================================
echo.
echo Bu dosya GoodbyeDPI'i arka planda otomatik baslayan bir Windows
echo hizmeti olarak kuracaktir.
echo.
echo ONEMLI: Bu dosyaya SAG TIKLAYIP "YONETICI OLARAK CALISTIR" demelisiniz.
echo Devam etmek icin bir tusa basin...
pause

sc stop "GoodbyeDPI" >nul 2>&1
sc delete "GoodbyeDPI" >nul 2>&1

sc create "GoodbyeDPI" binPath= "\"%~sdp0%_arch%\goodbyedpi.exe\" -5 --set-ttl 5 -q --doh --max-payload 1200 --blacklist \"%~sdp0blacklist_kyk.txt\"" start= "auto"
sc description "GoodbyeDPI" "GSB ve KYK yurt interneti icin optimize edilmis DPI atlatma servisi."
sc start "GoodbyeDPI"

echo.
echo ===================================================================
echo   Servis basariyla kuruldu ve arka planda baslatildi!
echo   Bilgisayarinizi yeniden baslatsaniz bile otomatik acilacaktir.
echo ===================================================================
pause
POPD
