<#
.NOTES
    Author:         Chris Stone <chris.stone@nuwavepartners.com>
    Date-Modified:  2025-06-25 12:17:55

.SYNOPSIS
    Installs the ConnectWise RMM Agent after verifying prerequisites.

.DESCRIPTION
    This script automates the installation of the ConnectWise RMM Agent. It performs the following tasks:

    1. Verifies that NuGet and PowerShell Gallery are available and configured. Ensures the "PS-WindowsInstaller" module is installed.
    2. Downloads the Agent MSI from the specified URI. Installs the MSI, passing the provided token as a property for tenant identification.

.PARAMETER Token
    A GUID string representing the authentication token for the ConnectWise RMM Agent. If not provided, the script
    will attempt to retrieve it from the registry path 'HKLM:\Software\Policies\NuWave\CWRMMToken'.

.PARAMETER AgentUri
    An absolute URI pointing to the location of the ConnectWise RMM Agent MSI file.

.EXAMPLE
    .\InstallAgent.ps1 -Token '12345678-1234-1234-1234-123456789012' -AgentUri 'https://example.com/agent.msi'
#>

param(
	[Parameter(Mandatory = $false)]
	[ValidateScript({ [GUID]::Parse($_) })]
	[string] $Token = (Get-ItemProperty -Path 'HKLM:\Software\Policies\NuWave' -ErrorAction SilentlyContinue).CWRMMToken,

	[Parameter(Mandatory = $false)]
	[ValidateScript({ [URI]::TryCreate($_, 'Absolute', [ref] $null) })]
	[string] $AgentUri = 'https://prod.setup.itsupport247.net/windows/BareboneAgent/32/X/MSI/setup'
)

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT

Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath ("NuWave_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")))
Write-Output ('Script Started ').PadRight(80, '-')

Invoke-EnvironmentCheck

$MSIPath = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([System.IO.Path]::GetRandomFileName() + ".msi")
Invoke-WebRequest -Uri $AgentUri -OutFile $MSIPath
Install-AgentMsi -MSIPath $MSIPath -Token $Token
Remove-Item -Path $MSIPath

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript
