### PowerShell Profile
function _setConst([string]$name, [string]$value) {
    if (-not (Get-Variable -Name $name -Scope Script -ErrorAction SilentlyContinue)) {
        Set-Variable -Name $name -Value $value -Option Constant -Scope Script
    }
}

_setConst "PROFILE_VERSION" "v2.1.0" # DO NOT MODIFY VERSION MANUALLY.
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
        ttask = @{ repo = "ttask"; exe = "ttask.exe" }
        moni = @{ repo = "moni"; exe = "moni.exe" }
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
Remove-Alias rm, ls -ErrorAction SilentlyContinue

function touch([string]$name) {
    if (Test-Path $name) { (Get-Item $name).LastWriteTime = Get-Date }
    else { New-Item -ItemType File -Path $name | Out-Null }
}

function rm {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Items)
    $recurse = $false; $force = $false; $paths = @()
    foreach ($a in $Items) {
        if ($a -match '^-[rRfF]+$') {
            if ($a -match '[rR]') { $recurse = $true }
            if ($a -match '[fF]') { $force = $true }
        }
        else { $paths += $a }
    }
    if ($paths) {
        $ea = if ($force) { 'SilentlyContinue' } else { 'Continue' }
        Remove-Item -Path $paths -Recurse:$recurse -Force:$force -ErrorAction $ea
    }
}
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

function grep {
    param(
        [Parameter(Position=0)][string]$Pattern,
        [Parameter(Position=1, ValueFromRemainingArguments=$true)][string[]]$Path,
        [switch]$r,
        [switch]$i
    )
    if ($Path) {
        Get-ChildItem -Path $Path -Recurse:$r -File -ErrorAction SilentlyContinue |
            Select-String -Pattern $Pattern -CaseSensitive:(-not $i)
    }
    else {
        $input | Select-String -Pattern $Pattern -CaseSensitive:(-not $i)
    }
}

function which($name) { Get-Command $name | Select-Object -ExpandProperty Definition }
function pkill($name) { Get-Process $name -ErrorAction SilentlyContinue | Stop-Process }
function pgrep($name) { Get-Process $name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id }
function head([string]$path, [int]$n = 10) { Get-Content $path -Head $n }
function tail([string]$path, [int]$n = 10, [switch]$f = $false) {
    Get-Content $path -Tail $n -Wait:$f
}

function ls([switch]$a, [Parameter(ValueFromRemainingArguments=$true)][string[]]$Path) {
    if (-not $Path) { $Path = '.' }
    Get-ChildItem -Path $Path -Force:$a | Format-Table -AutoSize
}

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
    $slnFiles = Get-ChildItem -Path (Get-Location).Path -Recurse -Include *.sln, *.slnf, *.slnx

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
    if (-not ('PolicyConfig' -as [type])) {
        Add-Type -TypeDefinition @'
using System.Runtime.InteropServices;
[Guid("f8679f50-850a-41cf-9c72-430f290290c8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IPolicyConfig {
    void _0(); void _1(); void _2(); void _3(); void _4(); void _5();
    void _6(); void _7(); void _8(); void _9(); void _10();
    void SetEndpointVisibility([MarshalAs(UnmanagedType.LPWStr)] string id, int visible);
}
[ComImport, Guid("870af99c-171d-4f9e-af0d-e63df40c2bc9")] class CPolicyConfigClient { }
public static class PolicyConfig {
    public static void SetVisible(string id, bool visible) =>
        ((IPolicyConfig)(new CPolicyConfigClient())).SetEndpointVisibility(id, visible ? 1 : 0);
}
'@
    }

    $root = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\MMDevices\Audio\Capture'
    $devs = Get-ChildItem $root -EA SilentlyContinue | ForEach-Object {
        [PSCustomObject]@{ Id = "{0.0.1.00000000}.$($_.PSChildName)"; State = Get-ItemPropertyValue $_.PSPath DeviceState }
    }
    if (!$devs) { Write-Host "No microphones found." -ForegroundColor Yellow; return }

    $mute = $devs.State -contains 1
    $targets = if ($mute) { $devs | Where-Object State -eq 1 } else { $devs | Where-Object State -ne 1 }
    $targets | ForEach-Object { [PolicyConfig]::SetVisible($_.Id, -not $mute) }
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

# zoxide init spawns a child process — cache its output to avoid ~15s cold-boot delay.
# Delete .zoxide-init.ps1 to force regeneration (e.g. after upgrading zoxide).
$zoxideCache = Join-Path (Split-Path -Parent $PROFILE) ".zoxide-init.ps1"
if (-not (Test-Path $zoxideCache)) {
    $init = if (Get-Command zoxide -ErrorAction SilentlyContinue) {
        zoxide init --cmd cd powershell | Out-String
    } else { "" }
    Set-Content -LiteralPath $zoxideCache -Value $init -Encoding utf8
}
. $zoxideCache