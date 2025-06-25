


# 1. Verify on a DC
# 2. Download Bundle (Script, Certificate, GPO Config)
# 2.1. Unpack, push Script
# 3. Apply GPO Config

param(
	[Parameter(Mandatory = $false)]
	[ValidateScript({ [URI]::TryCreate($_, 'Absolute', [ref] $null) })]
	[string] $BundleUri = 'https://github.com/nuwavepartners/connectwise_rmm/releases'
)

###################################################################### FUNCTIONS

#FUNCTIONS#

#################################################################### MAIN SCRIPT

Start-Transcript -Path (Join-Path -Path $env:TEMP -ChildPath ("NuWave_{0}.log" -f (Get-Date -Format "yyyy-MM-dd_HH-mm-ss")))
Write-Output ('Script Started ').PadRight(80, '-')

