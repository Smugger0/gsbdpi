@ECHO OFF
chcp 65001 >nul
PUSHD "%~sdp0"

echo ===================================================================
echo   GOODBYEDPI SERVISINI KALDIRMA
echo ===================================================================
echo.
echo ONEMLI: Bu dosyaya SAG TIKLAYIP "YONETICI OLARAK CALISTIR" demelisiniz.
echo Devam etmek icin bir tusa basin...
pause

sc stop "GoodbyeDPI"
sc delete "GoodbyeDPI"

echo.
echo ===================================================================
echo   GoodbyeDPI servisi basariyla durduruldu ve kaldirildi.
echo ===================================================================
pause
POPD
