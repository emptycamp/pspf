### PowerShell Profile
### Version 1.0


# Core functions ==================================================================================
function Test-CommandExists([string]$command) {
    return $null -ne (Get-Command $command -ErrorAction SilentlyContinue)
}

$DEFAULT_EDITOR = if (Test-CommandExists code) { "code" }
elseif (Test-CommandExists notepad++) { "notepad++" }
else { "notepad" }

Set-Alias -Name edit -Value $DEFAULT_EDITOR

function Update([string]$module) {
    switch ($module) {
        "ps" {
            Update-PowerShell
        }
        "pspf" {
            Update-PowerShellProfile
        }
        default {
            Write-Host "Unknown module specified, please select one of the following:" -ForegroundColor Red
            Write-Host " * ps" -ForegroundColor Red
            Write-Host " * pspf" -ForegroundColor Red
        }
    }
}

function Update-PowerShell {
    Write-Host "Checking for PowerShell updates..." -ForegroundColor Cyan

    try {
        $currentVersion = $PSVersionTable.PSVersion.ToString()
        $latestReleaseInfo = Invoke-RestMethod -Uri "https://api.github.com/repos/PowerShell/PowerShell/releases/latest"
        $latestVersion = $latestReleaseInfo.tag_name.Trim("v")

        if ($currentVersion -lt $latestVersion) {
            Write-Host "Found newer version $latestVersion, updating PowerShell..." -ForegroundColor Yellow
            winget upgrade -e --id "Microsoft.PowerShell" --accept-source-agreements --accept-package-agreements
            Write-Host "PowerShell has been updated, restart your shell to reflect changes." -ForegroundColor Magenta
        }
        else {
            Write-Host "PowerShell is up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to update PowerShell. Error: $_"
    }
}

function Update-PowerShellProfile {
    Write-Host "Updating PowerShell profile..." -ForegroundColor Cyan

    $profileName = Split-Path -Leaf $PROFILE
    $profileDirectory = Split-Path -Parent $PROFILE

    $tempProfilePath = "$env:temp/$profileName"
    $tempThemePath = "$env:temp/theme.yaml"

    try {
        $githubRepoUrl = "https://raw.githubusercontent.com/$PROFILE_REPO/main"
        Invoke-RestMethod "$githubRepoUrl/$profileName" -OutFile $tempProfilePath
        Invoke-RestMethod "$githubRepoUrl/theme.yaml" -OutFile $tempThemePath

        $oldProfileHash = Get-FileHash $PROFILE
        $newProfilehash = Get-FileHash $tempProfilePath
        if ($newProfilehash.Hash -ne $oldProfileHash.Hash) {
            Copy-Item -Path $tempProfilePath -Destination $PROFILE -Force
            Write-Host "Profile has been updated, restart your shell to reflect changes." -ForegroundColor Magenta
        }
        else {
            Write-Host "PowerShell is up to date." -ForegroundColor Green
        }

        $oldThemeHash = Get-FileHash "$profileDirectory/theme.yaml"
        $newThemeHash = Get-FileHash $tempThemePath
        if ($oldThemeHash.Hash -ne $newThemeHash.Hash) {
            Copy-Item -Path $tempThemePath -Destination "$profileDirectory/theme.yaml" -Force
            Write-Host "Theme has been updated." -ForegroundColor Magenta
            . $PROFILE
        }
        else {
            Write-Host "Theme is up to date." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to update Profile. Error: $_"
    }
    finally {
        Remove-Item $tempProfilePath -ErrorAction SilentlyContinue
        Remove-Item $tempThemePath -ErrorAction SilentlyContinue
    }
}
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
function tail([string]$path, [int]$n = 10, [switch]$f = $false) { Get-Content $path -Tail $n -Wait:$f }
function ls { Get-ChildItem -Path . -Force | Format-Table -AutoSize }

# Aliases
Set-Alias -Name su -Value Admin
# =================================================================================================


# Custom functions ================================================================================
# Utils
function Edit-Profile { edit $PROFILE.CurrentUserAllHosts }
function Get-PublicIp { (Invoke-WebRequest http://ifconfig.me/ip).Content }
function Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent())
    .IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

    if (!$isAdmin) {
        $psCommand = if ($PSVersionTable.PSEdition -eq "Core") { "pwsh" } else { "powershell" }
        Start-Process $psCommand "-NoExit -Command Set-Location -Path '$(Get-Location)'" -Verb RunAs
    }
}

# Navigation
function desk { Set-Location -Path $HOME\Desktop }
function down { Set-Location -Path $HOME\Downloads }

# Git controls
function gc([string]$msg) { git commit -m "$msg" }
Set-Alias -Name gc -Value gc -Force


# Visual studio
function repos {
    if (!(Test-Path -Path $REPOS_DIR -PathType Container)) {
        New-Item -Path $REPOS_DIR -ItemType Directory
    }

    Set-Location $REPOS_DIR
}

function repo {
    if (!(Test-Path -Path $REPOS_DIR -PathType Container)) {
        New-Item -Path $REPOS_DIR -ItemType Directory
    }

    $selected = Get-ChildItem $REPOS_DIR -Attributes Directory | Invoke-Fzf

    if ($selected) {
        Set-Location $selected
        [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
        return $true
    }
    else {
        return $false
    }
}

function vs {
    $slnFiles = Get-ChildItem -Path (Get-Location).Path -Recurse -Filter *.sln

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

Set-PSReadLineKeyHandler -Chord "Ctrl+d" -ScriptBlock {
    Get-ChildItem . -Attributes Directory | Invoke-Fzf | ForEach-Object { Set-Location $_ }
    [Microsoft.PowerShell.PSConsoleReadLine]::AcceptLine()
}

Set-PSReadLineKeyHandler -Chord "Ctrl+y" -ScriptBlock {
    $operationPerformed = Repo
    if ($operationPerformed) {
        Vs
    }
}

# TODO: file compare and excel compare
# function cmp {
#     git difftool --tool="winmerge" HEAD -y -d
# }

# Aliases
Set-Alias -Name nano -Value "notepad++"
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