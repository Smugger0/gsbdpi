@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Failed to load vcvars64.bat
    exit /b 1
)
cd /d "%~dp0"
cl.exe /nologo /O2 /W3 /MT /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS tools\kyk_test.c /Fe:kyk_test.exe /link shell32.lib advapi32.lib ws2_32.lib
if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed
    exit /b 1
)
del tools\kyk_test.obj 2>nul
del kyk_test.obj 2>nul
echo [SUCCESS] kyk_test.exe compiled successfully!
