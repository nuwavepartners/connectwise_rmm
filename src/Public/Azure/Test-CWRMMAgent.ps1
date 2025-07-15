<#
.NOTES
	Author:			Chris Stone <chris.stone@nuwavepartners.com>
	Date-Modified:	2025-06-27 16:51:02

 .SYNOPSIS
    Tests the status and service of the ConnectWise RMM Agent.

 .DESCRIPTION
    This script performs checks to verify the operational status of the ConnectWise RMM Agent.
    It checks if the agent's status is healthy and if the "ITSPlatform" service is running.

 .PARAMETER SkipServiceCheck
    If specified, the script will skip the check for the "ITSPlatform" service.
 .PARAMETER SkipStatusCheck
    If specified, the script will skip the general status check of the agent.
#>

param(
	[switch] $SkipServiceCheck,
	[switch] $SkipStatusCheck
)

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT


Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath ("NuWave_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")))
Write-Output ('Script Started ').PadRight(80, '-')

[int]$ExitResult = 0

if (!$PSBoundParameters.ContainsKey('SkipStatusCheck')) {
	if (!(Invoke-StatusCheck)) {
		Write-Output 'Status Check Failed'
		$ExitResult++
	}
}

if (!$PSBoundParameters.ContainsKey('SkipServiceCheck')) {
	if (!(Invoke-ServiceCheck -Service 'ITSPlatform')) {
		Write-Output 'ITSPlatform Service Not Running'
		$ExitResult++
	}
}

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript
Exit $ExitResult
