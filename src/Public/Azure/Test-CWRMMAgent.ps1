<#
.NOTES
	Author:			Chris Stone <chris.stone@nuwavepartners.com>
	Date-Modified:	2025-06-24 14:19:35

#>

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT

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
			exit 2
		}
	} else {
		Write-Output "$AgentService is running"
		Start-Sleep 3
		exit 0
	}
} else {
	Write-Output "Service Not Found."
	exit 1
}
