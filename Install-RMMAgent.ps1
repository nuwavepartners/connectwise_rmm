<#
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

.NOTES
    - Requires network access to the PowerShell Gallery and the Agent URI.
    - Assumes the MSI file is designed to accept a "TOKEN" property during installation.
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
	[string]$AgentUri = 'https://nuwave.link/rmm/ITSPlatform_latest.msi'
)

[Net.ServicePointManager]::SecurityProtocol = [System.Enum]::GetValues([System.Net.SecurityProtocolType]) | Where-Object { $_ -match 'Tls' };

# Step 1: Check and Start the Service
$AgentService = "ITSPlatform"
if ((Get-Service $AgentService -ErrorAction SilentlyContinue)) {
	if ((Get-Service $AgentService).Status -ne "Running") {
		Write-Output "$AgentService service is not running. Attempting to start it..."
		try {
			$r = Start-Service -Name $AgentService -PassThru
			If ($r.Status -eq "Running") {
				Write-Output "$AgentService service started."
				exit 0
			}
		} catch {
			Write-Error "Failed to start the $AgentService service: $_"
			exit 1
		}
	}
}

# Step 2: Check NuGet and PowerShell Gallery
if (-not (Get-PackageProvider -Name NuGet -ListAvailable)) {
	Write-Output "Installing NuGet package provider..."
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force
}

if (-not (Get-PSRepository -Name PSGallery -ErrorAction SilentlyContinue)) {
	Write-Output "Registering PSGallery..."
	Register-PSRepository -Default -Name PSGallery -InstallationPolicy Trusted
} else {
	# Ensure PSGallery is already trusted
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
}



# Step 3: Install PS-WindowsInstaller Module
if (!(Get-Module PS-WindowsInstaller -ListAvailable)) {
	Write-Output "Installing PS-WindowsInstaller module..."
	try {
		Install-Module PS-WindowsInstaller -Force -Scope CurrentUser
	} catch {
		Write-Error "Failed to install PS-WindowsInstaller module: $_"
		exit 1
	}
}

# Step 4: Download Agent MSI
$downloadPath = "$env:TEMP\agent.msi"
try {
	Invoke-WebRequest -Uri $AgentUri -OutFile $downloadPath
} catch {
	Write-Error "Failed to download Agent MSI: $_"
	exit 1
}

# Step 5: Install Agent MSI with PS-WindowsInstaller
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

# SIG # Begin signature block
# MIIF6QYJKoZIhvcNAQcCoIIF2jCCBdYCAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCD26EAT+0ULHP2T
# 01J6ddC2clq+zZQO+5kosEBYrODXfaCCA0IwggM+MIICJqADAgECAhBZVP3hQBiZ
# h0jf8jC4J2H6MA0GCSqGSIb3DQEBCwUAMDcxNTAzBgNVBAMMLENocmlzIFN0b25l
# IDxjaHJpcy5zdG9uZUBudXdhdmVwYXJ0bmVycy5jb20+MB4XDTIwMDIxODIxNDE0
# MFoXDTI1MDIxODIxNTE0MVowNzE1MDMGA1UEAwwsQ2hyaXMgU3RvbmUgPGNocmlz
# LnN0b25lQG51d2F2ZXBhcnRuZXJzLmNvbT4wggEiMA0GCSqGSIb3DQEBAQUAA4IB
# DwAwggEKAoIBAQCg62030xLyXQrQxKA3U1sLBsCbsMuG8CNF0nPBbnx8wy1xSVmR
# NjDj6vHQrrXCEoDPGThIEZfAi2BKu+BiW93pKyYvjH4KluYPaKfpM8DrT1gTfnVJ
# 8W8IMhlO8LptwCV86aLYhcjtLX2Toa130u1uxrr6YrjQ2PQGsG7BUordtbd4vGvD
# etCTtH3il+sHojE1COSwRUQNSY/3xSGm4otjZHg3sGcFK4KzcK4M572nDPXZeuFr
# laBOum+duPBQOo5Za6363tNRpBNff7SNCcftmmA+Wy+Uq8r9/fZR6G9hFm4PB4DF
# dNK5VCkb+qmWa4XaxfEy/EnyZCuk7cH6sJVZAgMBAAGjRjBEMA4GA1UdDwEB/wQE
# AwIHgDATBgNVHSUEDDAKBggrBgEFBQcDAzAdBgNVHQ4EFgQUolHkzzvm5ChXKTKR
# wiMqPbfq+qYwDQYJKoZIhvcNAQELBQADggEBAGBrwbmZj03Wz7xZAcuWI1PYheNl
# xks59o5aIUehEKhnc3m3hC7swtL0MLpSwd15ahxoLjKLh7iEsUcvqkUa4Q3DE54s
# lbxfG8eT3YoH8GKpMeZb12dUKk9llqlQpoLzFzaLoixp7dNhi08BIv5LOUTHdM/X
# HDw07N4jzTAVzyTqUnRP4DddH51OQuNzruN2sSt8GmcADQElUaD/yvZ+BKfY8HBv
# HUTOOGpCByR5lqnoRhALnKM+rPlelkA1mWzNkHeVCg3jhNNQSScXtQvymsi07yVF
# zqfBq8h4+dsaIliRAEVDTGk1q7viUiB8bmCv/ht/LU91zehzwiO2EtmzGz8xggH9
# MIIB+QIBATBLMDcxNTAzBgNVBAMMLENocmlzIFN0b25lIDxjaHJpcy5zdG9uZUBu
# dXdhdmVwYXJ0bmVycy5jb20+AhBZVP3hQBiZh0jf8jC4J2H6MA0GCWCGSAFlAwQC
# AQUAoIGEMBgGCisGAQQBgjcCAQwxCjAIoAKAAKECgAAwGQYJKoZIhvcNAQkDMQwG
# CisGAQQBgjcCAQQwHAYKKwYBBAGCNwIBCzEOMAwGCisGAQQBgjcCARUwLwYJKoZI
# hvcNAQkEMSIEIIH/cMe5ipuPKp62DOgYmgX0fGHfQi12ikahZYDFftjiMA0GCSqG
# SIb3DQEBAQUABIIBAJMR+vghPqNsx/PF/So7kHgfOb0fvzFxWvKW+hV9rJurSg+N
# NmNhvSqDoIoIwMu/c6im7ZAjOM3MoraMSJUHbVU4ko2m8hfj7b7gC19599v2hbYN
# IKhUoklZ3uujb8YZA++TPOTR5YVwBDrT1F+tbV28izQheGVxDdPA+CiqqtwZi42J
# gSEzOqc2OeIbQcDZYE6Ue1tPXaO176QX/bby3gteFOrOAWfW1bBwZTKk0/FVQbdW
# CoWt7secL0rxjIMERazDaUNboUgmHBbrR12wXpvOwa4fkWiK5iYAA6l7vEAJ58hw
# Y2zQuwyB5nBP3W5dgHR0l9cykj57w0/RZSQS890=
# SIG # End signature block
