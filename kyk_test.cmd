@ECHO OFF
:: ===================================================================
::   GSB / KYK GOODBYEDPI OTOMATIK STRATEJI VE TEST ARACI
:: ===================================================================
chcp 65001 >nul
PUSHD "%~dp0"

"%~dp0kyk_test.exe" %*

POPD
