# Set the error action preference to stop the script on any error
$ErrorActionPreference = "Stop"

# Helpers =========================================================================================
# Writes output and exists application
function Fail([string]$errorMessage) {
    Write-Host $errorMessage -ForegroundColor Red
    exit 1
}

# Installs packages using winget
function Install-WingetPackages([string[]]$packages) {
    foreach ($package in $packages) {
        try {
            Write-Host "Installing $package package..."
            winget install -e --id $package --accept-source-agreements --accept-package-agreements | Out-Null
            Write-Host "$package package installed successfully." -ForegroundColor Green
        }
        catch {
            Fail "Failed to install $package package.`nError: $_"
        }
    }
}

# Installs modules from PSGallery
function Install-Modules([string[]]$modules) {
    foreach ($module in $modules) {
        try {
            Write-Host "Installing $module module..."
            Install-Module -Name $module -Repository PSGallery -Force | Out-Null
            Write-Host "$module module installed successfully." -ForegroundColor Green
        }
        catch {
            Fail "Failed to install $module module.`nError: $_"
        }
    }
}
# =================================================================================================


# Application functions ===========================================================================
<#
.DESCRIPTION
    Ensures environment is correct before starting installation

    Following conditions are ensuresd:
        1. You have admin privileges
        2. This script is running in PowerShell Core (solves issues automatically)
        3. You can reach github.com
#>
function Confirm-Environment {
    # Ensures admin privileges are granted
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
        Fail "This script must be run as admin!"
    }

    # Ensure script is running in PowerShell Core
    if ($PSVersionTable.PSEdition -ne "Core") {
        # Install PowerShell Core if not installed
        if (-not (Get-Command pwsh -ErrorAction SilentlyContinue)) {
            Install-WingetPackages Microsoft.PowerShell
        }

        # Restart the script in PowerShell Core with admin privileges
        Write-Host "Restarting script in PowerShell Core" -ForegroundColor Green
        Start-Process pwsh -ArgumentList "-NoExit -NoProfile -ExecutionPolicy RemoteSigned -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }

    # Ensures internet connection is present
    try {
        Test-Connection github.com -Count 1 -ErrorAction Stop | Out-Null
    }
    catch {
        Fail "This script must be run with internet connection!"
    }
}

<#
.DESCRIPTION
    This function updates powershell profile from given GitHub repo url

    Following conditions are ensuresd:
        1. Existing profile is backed-up
        2. Missing profile directory is created
        3. Profile is downloaded and updated
.PARAMETER GithubRepoUrl
    Base url of GitHub repository that contains appropriate profile
    Default profile name is: Microsoft.PowerShell_profile.ps1
#>
function Update-PowershellProfile([string]$githubRepoUrl) {
    $profileName = Split-Path -Leaf $PROFILE

    # Backup existing profile
    if (Test-Path -Path $PROFILE -PathType Leaf) {
        Get-Item -Path $PROFILE | Move-Item -Destination "$profileName.backup" -Force
    }
    else {
        $profileDirectory = Split-Path -Parent $PROFILE

        # Create profile directory if missing
        if (!(Test-Path -Path $profileDirectory -PathType Container)) {
            New-Item -Path $profileDirectory -ItemType Directory
        }
    }

    # Download and update PS profile
    try {
        Invoke-RestMethod "$githubRepoUrl/$profileName" -OutFile $PROFILE
        Write-Host "Created profile at $PROFILE" -ForegroundColor Green
    }
    catch {
        Fail "Failed to install PS Profile.`nError: $_"
    }
}

<#
.DESCRIPTION
    Installs specified Nerd Font if missing.
    https://www.nerdfonts.com/
.PARAMETER FontName
    Font names can be found under Assets in the v3.2.1 release.
    https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.2.1
#>
function Install-NerdFont([string]$fontName) {
    try {
        if ($null -eq (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
            Write-Host "Temporary adding OhMyPosh to environment path" -ForegroundColor Yellow
            $env:PATH += ";$HOME\AppData\Local\Programs\oh-my-posh\bin"
        }

        oh-my-posh font install $fontName
    }
    catch {
        Fail "Failed to install $fontName font.`nError: $_"
    }
}
# =================================================================================================


# Application logic ===============================================================================
Confirm-Environment
Install-WingetPackages JanDeDobbeleer.OhMyPosh, ajeetdsouza.zoxide, junegunn.fzf
Install-Modules Terminal-Icons, PSFzf
Install-NerdFont CascadiaCode
Update-PowershellProfile "https://github.com/emptycamp/pspf/raw/main"
# =================================================================================================
