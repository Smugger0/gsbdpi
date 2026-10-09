@ECHO OFF
:: ===================================================================
::   GSB / KYK GOODBYEDPI OTOMATIK STRATEJI VE TEST ARACI
:: ===================================================================
chcp 65001 >nul
PUSHD "%~dp0"

if exist "%~dp0kyk_test.exe" (
    "%~dp0kyk_test.exe" %*
) else (
    :: Fallback to powershell test if exe is missing
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0kyk_test.ps1" %*
)

POPD
