@echo off
setlocal
call "C:\Program Files\Microsoft Visual Studio\18\Community\VC\Auxiliary\Build\vcvars64.bat" >nul
if %errorlevel% neq 0 (
    echo [ERROR] Failed to load vcvars64.bat
    exit /b 1
)

set "SRC_DIR=%~dp0src"
set "WINDIVERT_DIR=C:\Users\smugg\.gemini\antigravity-ide\brain\0987f498-5437-42a7-9667-d13bae52a9a0\scratch\windivert_pkg\WinDivert-2.2.2-A"

cd /d "%SRC_DIR%"

cl.exe /nologo /O2 /W3 /DWIN32_LEAN_AND_MEAN /D_CRT_SECURE_NO_WARNINGS /D_CRT_NONSTDC_NO_DEPRECATE ^
    /I"%SRC_DIR%" /I"%SRC_DIR%\compat" /I"%WINDIVERT_DIR%\include" ^
    goodbyedpi.c dohproxy.c blackwhitelist.c dnsredir.c fakepackets.c service.c ttltrack.c ^
    utils\repl_str.c utils\getline.c compat\getopt.c ^
    /link /OUT:goodbyedpi.exe /LIBPATH:"%WINDIVERT_DIR%\x64" ^
    WinDivert.lib ws2_32.lib winhttp.lib advapi32.lib user32.lib

if %errorlevel% neq 0 (
    echo [ERROR] Compilation failed
    exit /b 1
)

echo [SUCCESS] goodbyedpi.exe compiled successfully!
