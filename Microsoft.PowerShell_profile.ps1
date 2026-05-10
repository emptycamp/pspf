### PowerShell Profile
function _setConst([string]$name, [string]$value) {
    if (-not (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name $name -Value $value -Option Constant -Scope Script
    }
}

_setConst "PROFILE_VERSION" "v0.6.0" # DO NOT MODIFY VERSION MANUALLY.
_setConst "PROFILE_USER" "emptycamp"
_setConst "PROFILE_REPO" "$PROFILE_USER/pspf"
_setConst "REPOS_DIR" "C:\repos"

function Update-Profile([string]$version="main") {
    $profileName = Split-Path -Leaf $PROFILE

    $tempProfilePath = "$env:temp/$profileName"

    if ([string]::IsNullOrEmpty($version)) {
        $version = "main"
    }

    if ($version[0] -match '\d') {
        $version = "v$version"
    }

    Write-Host "Updating PowerShell profile to version $version..." -ForegroundColor Cyan

    function Update-FileToLatest($newFile, $oldFile, $context) {
        if ((Get-FileHash $newFile).Hash -eq (Get-FileHash $oldFile).Hash) {
            Write-Host "$context is up to date." -ForegroundColor Green
        }
        else {
            Copy-Item -Path $newFile -Destination $oldFile -Force
            Write-Host "$context has been updated, restart your shell to reflect changes." `
                -ForegroundColor Magenta
        }
    }

    try {
        $githubRepoUrl = "https://raw.githubusercontent.com/$PROFILE_REPO/$version"
        Invoke-RestMethod "$githubRepoUrl/$profileName" -OutFile $tempProfilePath
        Update-FileToLatest $tempProfilePath $PROFILE "Profile"
        . $PROFILE
    }
    catch {
        Write-Error "Failed to update Profile. Error: $_"
    }
    finally {
        Remove-Item $tempProfilePath -ErrorAction SilentlyContinue
    }
}

function Get-Version { Write-Host "Profile version: $PROFILE_VERSION" }

function Install-Tool([string]$action, [string]$name) {
    $registry = @{
        tt = @{ repo = "tt"; exe = "tt.exe" }
    }

    if ($action -ne "add" -or !$name) {
        Write-Host "Usage: tool add <tool_name>" -ForegroundColor Red
        return
    }

    $tool = $registry[$name]
    if (-not $tool) {
        Write-Host "Unknown tool: $name" -ForegroundColor Red
        return
    }

    $toolsDir = Join-Path (Split-Path -Parent $PROFILE) "tools"
    if (!(Test-Path -Path $toolsDir -PathType Container)) {
        New-Item -Path $toolsDir -ItemType Directory | Out-Null
    }

    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if (";$userPath;" -notlike "*;$toolsDir;*") {
        $newUserPath = if ($userPath) { "$userPath;$toolsDir" } else { $toolsDir }
        [Environment]::SetEnvironmentVariable("Path", $newUserPath, "User")
    }
    if (";$env:Path;" -notlike "*;$toolsDir;*") {
        $env:Path = "$env:Path;$toolsDir"
    }

    try {
        $release = Invoke-RestMethod "https://api.github.com/repos/$PROFILE_USER/$($tool.repo)/releases/latest"
        $asset = $release.assets | Where-Object { $_.name -eq $tool.exe } | Select-Object -First 1
        if (-not $asset) { throw "Asset '$($tool.exe)' not found in latest release." }
        Invoke-WebRequest $asset.browser_download_url -OutFile (Join-Path $toolsDir $tool.exe)
        Write-Host "$name installed to $toolsDir" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install tool '$name'. Error: $_"
    }
}

# Aliases
Set-Alias -Name update -Value Update-Profile
Set-Alias -Name version -Value Get-Version
Set-Alias -Name tool -Value Install-Tool
# =================================================================================================


# Linux-like functions ============================================================================
function touch([string]$name) { New-Item -ItemType "file" -Path . -Name $name }
function uptime {
    if ($PSVersionTable.PSVersion.Major -eq 5) {
        Get-WmiObject win32_operatingsystem |
        Select-Object @{
            Name       = "LastBootUpTime";
            Expression = { $_.ConverttoDateTime($_.lastbootuptime) }
        } |
        Format-Table -HideTableHeaders
    }
    else {
        net statistics workstation |
        Select-String "since" |
        ForEach-Object { $_.ToString().Replace("Statistics since ", "") }
    }
}

function grep($regex, $dir) {
    if ($dir) {
        Get-ChildItem $dir | Select-String $regex
    }
    else {
        $input | select-string $regex
    }
}

function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }
function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process }
function pgrep($name) { Get-Process $name }
function head([string]$path, [int]$n) { Get-Content $path -Head $n }
function tail([string]$path, [int]$n = 10, [switch]$f = $false) {
    Get-Content $path -Tail $n -Wait:$f
}

function ls { Get-ChildItem -Path . -Force | Format-Table -AutoSize }

# Aliases
Set-Alias -Name su -Value admin
# =================================================================================================


# Custom functions ================================================================================
# Utils
function edit-profile() {
    code (Split-Path -Parent $PROFILE)
}

function pubip { (Invoke-WebRequest http://ifconfig.me/ip).Content }

function afk([int]$minutes, [switch]$sleep) {
    Add-Type -AssemblyName System.Windows.Forms
    $endTime = $null

    if ($minutes -gt 0) {
        $endTime = (Get-Date).AddMinutes($minutes)

        if ($sleep) {
            Write-Output "Your computer will afk for $minutes minutes and then sleep."
        } else {
            Write-Output "Your computer will afk for $minutes minutes."
        }
    } else {
        Write-Output "Your computer will afk infinitely."
    }

    while ($true) {
        [System.Windows.Forms.SendKeys]::SendWait("{NUMLOCK}")
        Start-Sleep -Milliseconds 200
        [System.Windows.Forms.SendKeys]::SendWait("{NUMLOCK}")
        Start-Sleep -Seconds 60

        if ($endTime -and (Get-Date) -ge $endTime) {
            break
        }
    }

    if ($endTime -and $sleep) {
        [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Suspend, $false, $true);
    }
}

function hiber([int]$minutes = 0) {
    Add-Type -AssemblyName System.Windows.Forms
    Write-Output "Your computer will hibernate in $minutes minutes."
    Start-Sleep -Seconds ($minutes * 60)
    [System.Windows.Forms.Application]::SetSuspendState([System.Windows.Forms.PowerState]::Hibernate, $false, $true);
}

function admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal]`
                [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                    [Security.Principal.WindowsBuiltInRole]::Administrator)

    if (!$isAdmin) {
        $psCommand = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
        Start-Process $psCommand "-NoExit -Command Set-Location -Path '$(Get-Location)'" `
            -Verb RunAs
    }
}

function _cmp([string]$pathA, [string]$pathB) {
    if ($pathA -and !$pathB) {
        Write-Host "Specify two paths to compare." -ForegroundColor Red
    }

    if ($pathA -and $pathB) {
        & "C:\Program Files (x86)\WinMerge\WinMergeU.exe" $pathA $pathB
    }
    else {
        git difftool --tool="winmerge" HEAD -y -d
    }
}

function ex([string]$path = ".") { explorer $path }



# Git controls

function web {
    $remoteUrl = git remote get-url origin

    if (-not $remoteUrl) {
        Write-Host "Could not retrieve the remote URL of the Git repository" -ForegroundColor Red
        return
    }

    if ($remoteUrl -match "^https://([^/]+)/(.*)") {
        $domain = $matches[1]
        $path = $matches[2]
    }
    elseif ($remoteUrl -match "^ssh://git@([^:/]+)(?::\d+)?/(.+)") {
        $domain = $matches[1]
        $path = $matches[2]
    }
    else {
        Write-Host "The remote URL format is not recognized" -ForegroundColor Red
        return
    }

    Start-Process "https://$domain/$path"
}

function tree {
    Start-Process "$env:LocalAppData\SourceTree\SourceTree.exe" -ArgumentList "-f $PWD"
}

# Navigation
function desk { Set-Location -Path ([Environment]::GetFolderPath("Desktop")) }
function down {
    Set-Location -Path (New-Object -ComObject Shell.Application).Namespace('shell:Downloads').Self.Path
}
function repos {
    if (!(Test-Path -Path $REPOS_DIR -PathType Container)) {
        New-Item -Path $REPOS_DIR -ItemType Directory
    }

    Set-Location $REPOS_DIR
}

function repo([switch]$operationStatus) {
    if (!(Test-Path -Path $REPOS_DIR -PathType Container)) {
        New-Item -Path $REPOS_DIR -ItemType Directory
    }

    $selected = Get-ChildItem $REPOS_DIR -Attributes Directory | Invoke-Fzf

    if ($selected) {
        Set-Location $selected
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        if ($operationStatus) { return $true }
    }
    elseif ($operationStatus) { return $false }
}

function vs {
    $slnFiles = Get-ChildItem -Path (Get-Location).Path -Recurse -Include *.sln, *.slnf

    if (-not $slnFiles) {
        Write-Host "Solution file not found" -ForegroundColor Red
    }
    elseif ($slnFiles.Count -gt 1) {
        $slnFiles | Invoke-Fzf | ForEach-Object { & $_ }
    }
    else {
        & $slnFiles.FullName
    }
}

function prox {
    $regKey="HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings"
    $proxyStatus = Get-ItemProperty -Path $regKey -Name ProxyEnable, ProxyServer

    if ($proxyStatus.ProxyEnable -eq 1) {
        Set-ItemProperty -Path $regKey -Name ProxyEnable -Value 0
        Write-Host "Proxy disabled." -ForegroundColor Red
    } else {
        Set-ItemProperty -Path $regKey -Name ProxyEnable -Value 1
        Set-ItemProperty -Path $regKey -Name ProxyServer -Value '127.0.0.1:8080'
        Write-Host "Proxy enabled with 127.0.0.1:8080." -ForegroundColor Green
    }
}

function mute {
    Import-Module AudioDeviceCmdlets -ErrorAction Stop
    $devices = @(Get-AudioDevice -List | Where-Object Type -eq "Recording")
    if (!$devices) {
        Write-Host "No active input devices found." -ForegroundColor Yellow
        return
    }

    $mute = ($devices | Where-Object { -not $_.Device.AudioEndpointVolume.Mute }).Count -gt 0
    $devices | ForEach-Object { $_.Device.AudioEndpointVolume.Mute = $mute }
    Write-Host ($(if ($mute) { "Muted" } else { "Unmuted" }))
}

Set-PSReadLineKeyHandler -Chord "Ctrl+y" -ScriptBlock {
    $operationPerformed = Repo -OperationStatus
    if ($operationPerformed) {
        Vs
    }
}

# Aliases
Set-Alias -Name nano -Value "notepad++"
Set-Alias -Name mitm -Value "mitmweb"
# =================================================================================================

Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })