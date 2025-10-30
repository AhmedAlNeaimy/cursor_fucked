# Reset Cursor/Qoder on Windows
# PowerShell script for resetting device identifiers

param(
    [string]$App = "Cursor",
    [switch]$Restore
)

Write-Host "Targeting application: $App"

# --- Check PowerShell version ---
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Error "PowerShell 5.0 or higher is required"
    exit 1
}

# --- Application-Specific Configurations ---
$AppConfig = @{
    Cursor = @{
        ProcessName = "Cursor"
        AppPath = "$env:LOCALAPPDATA\Programs\Cursor"
        StoragePath = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
    }
    Qoder = @{
        ProcessName = "Qoder"
        AppPath = "$env:LOCALAPPDATA\Programs\Qoder"
        StoragePath = "$env:APPDATA\Qoder\User\globalStorage\storage.json"
    }
}

if (-not $AppConfig.ContainsKey($App)) {
    Write-Error "Unsupported application '$App'. Supported apps are 'Cursor' and 'Qoder'."
    exit 1
}

$Config = $AppConfig[$App]
$ProcessName = $Config.ProcessName
$AppPath = $Config.AppPath
$StoragePath = $Config.StoragePath
$BackupAppPath = "$AppPath.backup"

# --- Functions ---
function Generate-MacId {
    $uuid = [guid]::NewGuid().ToString().ToLower()
    $chars = $uuid.ToCharArray()
    $chars[14] = '4'
    $randomHex = Get-Random -Minimum 0 -Maximum 16
    $newChar = (($randomHex -band 0x3) -bor 0x8).ToString("x")
    $chars[19] = $newChar
    return -join $chars
}

function Generate-UniqueId {
    $uuid1 = [guid]::NewGuid().ToString("N")
    $uuid2 = [guid]::NewGuid().ToString("N")
    return "$uuid1$uuid2"
}

function Restore-Backup {
    Write-Host "Starting restore operation..."
    
    if (Test-Path "${StoragePath}.bak") {
        try {
            Copy-Item "${StoragePath}.bak" $StoragePath -Force
            Write-Host "Restored storage.json for $App"
        }
        catch {
            Write-Warning "Failed to restore storage.json: $_"
        }
    }
    else {
        Write-Warning "Backup file for storage.json does not exist"
    }

    if (Test-Path $BackupAppPath) {
        Write-Host "Restoring $App application..."
        
        Stop-AppProcess
        Start-Sleep -Seconds 2
        
        try {
            if (Test-Path $AppPath) {
                Remove-Item $AppPath -Recurse -Force
            }
            Move-Item $BackupAppPath $AppPath -Force
            Write-Host "Restored $App application"
        }
        catch {
            Write-Warning "Failed to restore application: $_"
        }
    }
    else {
        Write-Warning "Backup for $App application does not exist"
    }

    Write-Host "Restore operation completed"
    exit 0
}

function Stop-AppProcess {
    $processes = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
    if ($processes) {
        Write-Host "$App is running. Please close it before continuing..."
        Write-Host "Waiting for $App process to exit..."
        
        while (Get-Process -Name $ProcessName -ErrorAction SilentlyContinue) {
            Start-Sleep -Seconds 1
        }
    }
    Write-Host "$App has been closed, continuing execution..."
}

# --- Main Execution ---
if ($Restore) {
    Restore-Backup
}

# --- Check if running as Administrator ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Warning "Running without administrator privileges. Some operations may fail."
    Write-Host "To run as administrator, right-click PowerShell and select 'Run as Administrator'"
    $response = Read-Host "Continue anyway? (y/n)"
    if ($response -ne 'y') {
        exit 0
    }
}

# --- Stop Application ---
Stop-AppProcess

# --- Update Storage File ---
if (Test-Path $StoragePath) {
    Write-Host "Backing up storage.json..."
    try {
        Copy-Item $StoragePath "${StoragePath}.bak" -Force
        Write-Host "Backup created at: ${StoragePath}.bak"
    }
    catch {
        Write-Error "Unable to backup storage.json: $_"
        exit 1
    }

    Write-Host "Updating device identifiers..."
    try {
        $storageContent = Get-Content $StoragePath -Raw | ConvertFrom-Json
        
        $newId = Generate-UniqueId
        $newMacId = Generate-MacId
        $newDeviceId = [guid]::NewGuid().ToString()
        $newSqmId = "{$([guid]::NewGuid().ToString().ToUpper())}"

        $storageContent | Add-Member -MemberType NoteProperty -Name "telemetry.machineId" -Value $newId -Force
        $storageContent | Add-Member -MemberType NoteProperty -Name "telemetry.macMachineId" -Value $newMacId -Force
        $storageContent | Add-Member -MemberType NoteProperty -Name "telemetry.devDeviceId" -Value $newDeviceId -Force
        $storageContent | Add-Member -MemberType NoteProperty -Name "telemetry.sqmId" -Value $newSqmId -Force

        $storageContent | ConvertTo-Json -Depth 10 | Set-Content $StoragePath -Encoding UTF8

        Write-Host "Successfully updated all IDs for $App:"
        Write-Host "New telemetry.machineId: $newId"
        Write-Host "New telemetry.macMachineId: $newMacId"
        Write-Host "New telemetry.devDeviceId: $newDeviceId"
        Write-Host "New telemetry.sqmId: $newSqmId"
    }
    catch {
        Write-Error "Failed to update storage.json: $_"
        exit 1
    }
}
else {
    Write-Warning "storage.json not found at $StoragePath. Skipping ID reset."
}

# --- Modify Application Files ---
if (-not (Test-Path $AppPath)) {
    Write-Warning "$App not found at $AppPath"
    Write-Host "Storage IDs have been updated. You can reinstall $App to complete the process."
    exit 0
}

Write-Host "Backing up application files..."
try {
    if (Test-Path $BackupAppPath) {
        Remove-Item $BackupAppPath -Recurse -Force
    }
    Copy-Item $AppPath $BackupAppPath -Recurse -Force
    Write-Host "Application backup created at: $BackupAppPath"
}
catch {
    Write-Error "Failed to backup application: $_"
    exit 1
}

$appFiles = @(
    "$AppPath\resources\app\out\main.js",
    "$AppPath\resources\app\out\vs\code\node\cliProcessMain.js"
)

foreach ($file in $appFiles) {
    if (-not (Test-Path $file)) {
        Write-Warning "File $file does not exist"
        continue
    }

    Write-Host "Modifying file: $file"
    try {
        $backupFile = "$file.bak"
        Copy-Item $file $backupFile -Force

        $content = Get-Content $file -Raw -Encoding UTF8
        
        $pattern = 'IOPlatformUUID'
        if ($content -match $pattern) {
            $uuidPos = $content.IndexOf("IOPlatformUUID")
            $beforeUuid = $content.Substring(0, $uuidPos)
            $lastSwitchPos = $beforeUuid.LastIndexOf("switch")
            
            if ($lastSwitchPos -ge 0) {
                $newContent = $content.Substring(0, $lastSwitchPos) + 
                             "return crypto.randomUUID();`n" + 
                             $content.Substring($lastSwitchPos)
                
                Set-Content $file $newContent -Encoding UTF8 -NoNewline
                Write-Host "Successfully modified file: $file"
            }
            else {
                Write-Warning "switch keyword not found in $file"
            }
        }
        else {
            Write-Warning "IOPlatformUUID not found in $file"
        }
    }
    catch {
        Write-Warning "Failed to modify file ${file}: $_"
        if (Test-Path "$file.bak") {
            Copy-Item "$file.bak" $file -Force
        }
    }
}

Write-Host ""
Write-Host "All operations completed for $App!"
Write-Host "Original application has been backed up at: $BackupAppPath"
Write-Host ""
Write-Host "To restore original setup, run:"
Write-Host "  .\reset.ps1 -App $App -Restore"
Write-Host ""
Write-Host "You can now start $App and sign in with a new account."
