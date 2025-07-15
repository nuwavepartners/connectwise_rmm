<#
.NOTES
    Author:         Chris Stone <chris.stone@nuwavepartners.com>
    Date-Modified:  2025-06-27 16:46:42

.SYNOPSIS
    Installs an Agent MSI after verifying prerequisites.

.DESCRIPTION
    This script automates the installation of an Agent MSI. It performs the following tasks:

    1. Checks if the 'ITSPlatform' service is running and starts it if necessary.
    2. Verifies that NuGet and PowerShell Gallery are available and configured. Ensures the 'PS-WindowsInstaller' module is installed.
    3. Downloads the Agent MSI from the specified URI. Installs the MSI, passing the provided token as a property.

.PARAMETER Token
    A mandatory GUID string representing the authentication token for the Agent.

.PARAMETER AgentUri
    A mandatory absolute URI pointing to the location of the Agent MSI file.

.EXAMPLE
    Install-CWRMMAgent -Token '12345678-1234-1234-1234-123456789012' -AgentUri 'https://example.com/agent.msi'
.EXAMPLE
    Install-CWRMMAgent -Token '12345678-1234-1234-1234-123456789012' -SkipServiceCheck -SkipStatusCheck
.EXAMPLE
    Install-CWRMMAgent -Token '12345678-1234-1234-1234-123456789012' -SkipAgentInstall
#>

param(
	[Parameter(Mandatory = $true)]
	[ValidateScript({ [GUID]::Parse($_) })]
	[string] $Token,

	[Parameter(Mandatory = $false)]
	[ValidateScript({ [URI]::TryCreate($_, 'Absolute', [ref] $null) })]
	[string] $AgentUri = 'https://prod.setup.itsupport247.net/windows/BareboneAgent/32/X/MSI/setup',

	[switch] $SkipServiceCheck,
	[switch] $SkipStatusCheck,
	[switch] $SkipAgentInstall
)

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT

Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath ('NuWave_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')))
Write-Output ('Script Started ').PadRight(80, '-')

$AlreadyInstalled = 0

# Checks
if (!$PSBoundParameters.ContainsKey('SkipStatusCheck')) {
	if (Invoke-StatusCheck) {
		Write-Output 'Status Check Working'
		$AlreadyInstalled++
	}
}

if (!$PSBoundParameters.ContainsKey('SkipServiceCheck')) {
	if (Invoke-ServiceCheck -Service 'ITSPlatform') {
		Write-Output 'ITSPlatform Service Running Already'
		$AlreadyInstalled++
	}
}

# Install
if (!$PSBoundParameters.ContainsKey('SkipAgentInstall') -and ($AlreadyInstalled -le 0)) {
	# Check Environment
	Write-Verbose 'Checking TLS Protocols'
	[Net.ServicePointManager]::SecurityProtocol = [System.Enum]::GetValues([System.Net.SecurityProtocolType]) | Where-Object { $_ -match 'Tls' };

	Write-Verbose 'Checking Execution Policy'
	if (@('Unrestricted', 'RemoteSigned', 'Bypass') -notcontains (Get-ExecutionPolicy -Scope Process)) {
		Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
	}

	# Download
	$MSIPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.IO.Path]::GetRandomFileName() + '.msi')
	Write-Verbose ('Downloading {0} {1}' -f $AgentUri, $MSIPath)
	Invoke-WebRequest -Uri $AgentUri -OutFile $MSIPath

	# Install
	Write-Verbose 'Installing $MSIPath'
	$Installer = New-Object -ComObject WindowsInstaller.Installer
	$Installer.GetType().InvokeMember('UILevel', [System.Reflection.BindingFlags]::SetProperty, $null, $Installer, 2)
	$Session = $Installer.GetType().InvokeMember('OpenPackage', [System.Reflection.BindingFlags]::InvokeMethod, $null, $Installer, $MSIPath)
	$Session.GetType().InvokeMember('Property', [System.Reflection.BindingFlags]::SetProperty, $null, $Session, @('TOKEN', $Token))
	$Session.GetType().InvokeMember('DoAction', [System.Reflection.BindingFlags]::InvokeMethod, $null, $Session, 'INSTALL')
	Start-Sleep -Seconds 5
	Remove-Item -Path $MSIPath -ErrorAction SilentlyContinue
}

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript
