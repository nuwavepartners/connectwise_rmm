<#
.NOTES
    Author:         Chris Stone <chris.stone@nuwavepartners.com>
    Date-Modified:  2025-06-25 12:18:04

.SYNOPSIS
    Installs an Agent MSI after verifying prerequisites.

.DESCRIPTION
    This script automates the installation of an Agent MSI. It performs the following tasks:

    1. Checks if the "ITSPlatform" service is running and starts it if necessary.
    2. Verifies that NuGet and PowerShell Gallery are available and configured. Ensures the "PS-WindowsInstaller" module is installed.
    3. Downloads the Agent MSI from the specified URI. Installs the MSI, passing the provided token as a property.

.PARAMETER Token
    A mandatory GUID string representing the authentication token for the Agent.

.PARAMETER AgentUri
    A mandatory absolute URI pointing to the location of the Agent MSI file.

.EXAMPLE
    .\InstallAgent.ps1 -Token '12345678-1234-1234-1234-123456789012' -AgentUri 'https://example.com/agent.msi'
#>

param(
	[Parameter(Mandatory = $true)]
	[ValidateScript({ [GUID]::Parse($_) })]
	[string] $Token,

	[Parameter(Mandatory = $false)]
	[ValidateScript({ [URI]::TryCreate($_, 'Absolute', [ref] $null) })]
	[string] $AgentUri = 'https://prod.setup.itsupport247.net/windows/BareboneAgent/32/X/MSI/setup',

	[switch] $SkipServiceCheck,
	[switch] $SkipStatusCheck
)

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT

Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath ("NuWave_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")))
Write-Output ('Script Started ').PadRight(80, '-')

# Checks
if (!$PSBoundParameters.ContainsKey('SkipStatusCheck')) {
	if (Invoke-StatusCheck) {
		Write-Output 'Status Check Working'
		Write-Output ('Script Finished ').PadRight(80, '-')
		Stop-Transcript
		Exit 0
	}
}

if (!$PSBoundParameters.ContainsKey('SkipServiceCheck')) {
	if (Invoke-ServiceCheck -Service 'ITSPlatform') {
		Write-Output 'ITSPlatform Service Running Already'
		Write-Output ('Script Finished ').PadRight(80, '-')
		Stop-Transcript
		Exit 0
	}
}

# Install
Invoke-EnvironmentCheck

$MSIPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.IO.Path]::GetRandomFileName() + ".msi")
Invoke-WebRequest -Uri $AgentUri -OutFile $MSIPath
Install-AgentMsi -MSIPath $MSIPath -Token $Token
Remove-Item -Path $MSIPath

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript
