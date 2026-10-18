@echo off
setlocal
where mvn >nul 2>nul
if %ERRORLEVEL% equ 0 (
    mvn %*
) else if exist "D:\idealc\IntelliJ IDEA 2025.3.2\plugins\maven\lib\maven3\bin\mvn.cmd" (
    "D:\idealc\IntelliJ IDEA 2025.3.2\plugins\maven\lib\maven3\bin\mvn.cmd" %*
) else (
    echo [ERROR] Maven not found in PATH or standard IntelliJ location.
    exit /b 1
)
