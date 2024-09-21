### PowerShell Profile
$PROFILE_VERSION = "v0.1.0"

# Core functions ==================================================================================
function Test-CommandExists([string]$command) {
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}

$DEFAULT_EDITOR = if (Test-CommandExists code) { "code" }
elseif (Test-CommandExists notepad++) { "notepad++" }
else { "notepad" }

function Update-Profile([string]$version="main") {
    $profileName = Split-Path -Leaf $PROFILE
    $profileDirectory = Split-Path -Parent $PROFILE

    $tempProfilePath = "$env:temp/$profileName"
    $tempThemePath = "$env:temp/theme.yaml"

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
        Invoke-RestMethod "$githubRepoUrl/theme.yaml" -OutFile $tempThemePath
        Update-FileToLatest $tempProfilePath $PROFILE "Profile"
        Update-FileToLatest $tempThemePath "$profileDirectory/theme.yaml" "Theme"
        . $PROFILE
    }
    catch {
        Write-Error "Failed to update Profile. Error: $_"
    }
    finally {
        Remove-Item $tempProfilePath -ErrorAction SilentlyContinue
        Remove-Item $tempThemePath -ErrorAction SilentlyContinue
    }
}

function Get-Version { Write-Host "Profile version: $PROFILE_VERSION" }

# Aliases
Set-Alias -Name edit -Value $DEFAULT_EDITOR
Set-Alias -Name update -Value Update-Profile
Set-Alias -Name version -Value Get-Version
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
function edit-profile([switch]$main) {
    if ($main) {
        if (Test-CommandExists code) {
            code (Split-Path -Parent $PROFILE)
        }
        else {
            edit $PROFILE
        }
    }
    else {
        edit $PROFILE.CurrentUserAllHosts
    }
}

function pubip { (Invoke-WebRequest http://ifconfig.me/ip).Content }

function afk {
    Add-Type -AssemblyName 'System.Windows.Forms'

    while ($true) {
        [System.Windows.Forms.SendKeys]::SendWait("+")
        Start-Sleep -Seconds 60
    }
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

function cmp([string]$pathA, [string]$pathB) {
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
function commit([string]$msg) { git commit -m "$msg" }

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
    elseif ($remoteUrl -match "^git@([^:]+):(.+)") {
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
function desk { Set-Location -Path $HOME\Desktop }
function down { Set-Location -Path $HOME\Downloads }
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
    $slnFiles = Get-ChildItem -Path (Get-Location).Path -Recurse -Filter *.sln*

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

Set-PSReadLineKeyHandler -Chord "Ctrl+d" -ScriptBlock {
    Get-ChildItem . -Attributes Directory | Invoke-Fzf | ForEach-Object { Set-Location $_ }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
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


# Setup terminal ==================================================================================
Import-Module -Name Terminal-Icons
Set-PsFzfOption -PSReadlineChordProvider "Ctrl+t" -PSReadlineChordReverseHistory "Ctrl+r"
oh-my-posh init pwsh --config "$(Split-Path -Parent $PROFILE)\theme.yaml" | Invoke-Expression
Invoke-Expression (& { (zoxide init --cmd cd powershell | Out-String) })

Set-PSReadLineOption -PredictionSource History
Set-PSReadLineOption -PredictionViewStyle InlineView

$REPOS_DIR = "C:\repos"
$PROFILE_REPO = "emptycamp/pspf"
# =================================================================================================
