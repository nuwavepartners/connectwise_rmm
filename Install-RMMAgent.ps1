<#
.NOTES
	Author:			Chris Stone <chris.stone@nuwavepartners.com>
	Date-Modified:	2024-12-05 15:00:08

.SYNOPSIS
    Installs an Agent MSI after verifying prerequisites.

.DESCRIPTION
    This script automates the installation of an Agent MSI. It performs the following tasks:

    1. Checks if the "ITSPlatform" service is running and starts it if necessary.
    2. Verifies that NuGet and PowerShell Gallery are available and configured.
    3. Ensures the "PS-WindowsInstaller" module is installed.
    4. Downloads the Agent MSI from the specified URI.
    5. Installs the MSI, passing the provided token as a property.

.PARAMETER Token
    A mandatory GUID string representing the authentication token for the Agent.

.PARAMETER AgentUri
    A mandatory absolute URI pointing to the location of the Agent MSI file.

.EXAMPLE
    .\InstallAgent.ps1 -Token '12345678-1234-1234-1234-123456789012' -AgentUri 'https://example.com/agent.msi'
#>

param(
	[Parameter(Mandatory = $true)]
	[ValidateScript({
			[GUID]::Parse($_)
		})]
	[string]$Token,

	[Parameter(Mandatory = $false)]
	[ValidateScript({
			[URI]::TryCreate($_, 'Absolute', [ref] $null)
		})]
	[string]$AgentUri = 'https://prod.setup.itsupport247.net/windows/BareboneAgent/32/X/MSI/setup'
)

Start-Transcript -Path (Join-Path $env:TEMP ("NuWave_{0}.log" -f (Get-Date -Format "s")))
Write-Output ('Script Started ').PadRight(80, '-')
[Net.ServicePointManager]::SecurityProtocol = [System.Enum]::GetValues([System.Net.SecurityProtocolType]) | Where-Object { $_ -match 'Tls' };

# Step 1: Check and Start the Service
$AgentService = "ITSPlatform"
Write-Output "Checking Service..."
if ((Get-Service $AgentService -ErrorAction SilentlyContinue)) {
	if ((Get-Service $AgentService).Status -ne "Running") {
		Write-Output "$AgentService service is not running. Attempting to start it..."
		try {
			$r = Start-Service -Name $AgentService -PassThru
			If ($r.Status -eq "Running") {
				Write-Output "$AgentService service started."
				Start-Sleep 3
				exit 0
			}
		} catch {
			Write-Error "Failed to start the $AgentService service: $_"
			exit 1
		}
	} else {
		Write-Output "$AgentService is running"
		Start-Sleep 3
		exit 0
	}
} else {
	Write-Output "Service Not Found."
}

# Step 2: Check Environment
# BUG Get-PackageProvider and Get-PSRepository seem to hang PowerShell sometimes.
Write-Output "Checking Execution Policy"
if (@('Unrestricted', 'RemoteSigned', 'Bypass') -notcontains (Get-ExecutionPolicy -Scope Process)) {
	Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
}
Write-Output "Checking NuGet and PowerShell Gallery"
# if (-not (Get-PackageProvider -Name NuGet -ErrorAction SilentlyContinue)) {
# 	Write-Output "Installing NuGet package provider..."
Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
# } else {
# 	Write-Output "NuGet Found"
# }

# if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
# 	Write-Output "Registering PSGallery..."
# 	Register-PSRepository -Default -Name PSGallery -InstallationPolicy Trusted
# } else {
# Ensure PSGallery is already trusted
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
# 	Write-Output "PSGallery Trusted"
# }

# Step 3: Install PS-WindowsInstaller Module
Write-Output "Checking PS-WindowsInstaller"
if (!(Get-Module PS-WindowsInstaller -ListAvailable)) {
	Write-Output "Installing PS-WindowsInstaller module..."
	try {
		if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
			Install-Module PS-WindowsInstaller -Force -Scope AllUsers
		} else {
			Install-Module PS-WindowsInstaller -Force -Scope CurrentUser
		}
		Import-Module PS-WindowsInstaller
	} catch {
		Write-Error "Failed to install PS-WindowsInstaller module: $_"
		exit 1
	}
}

# Step 4: Download Agent MSI
Write-Output "Downloading Agent"
$downloadPath = "$env:TEMP\agent.msi"

if (Test-Path $downloadPath) {
	try {
		Remove-Item $downloadPath -Force
	} catch {
		Write-Error "Failed to delete existing file at ${downloadPath}: $_"
		exit 1
	}
}

try {
	Invoke-WebRequest -Uri $AgentUri -OutFile $downloadPath
} catch {
	Write-Error "Failed to download Agent MSI: $_"
	exit 1
}

# Step 5: Install Agent MSI with PS-WindowsInstaller
Write-Output "Installing Agent"
try {
	$installer = New-WindowsInstallerInstaller
	Set-WindowsInstallerInstallerUILevel -UILevel 2 -Installer $installer
	$session = Open-WindowsInstallerPackage -PackagePath $downloadPath
	Set-WindowsInstallerSessionProperty -Session $session -PropertyName 'TOKEN' -PropertyValue $Token
	Invoke-WindowsInstallerSessionAction -Session $session -Action 'INSTALL'
} catch {
	Write-Error "Failed to install Agent MSI: $_"
	exit 1
} finally {
	Remove-Item $downloadPath -Force
}

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript
