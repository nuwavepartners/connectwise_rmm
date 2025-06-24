function Invoke-ServiceCheck {
	param(
		[Parameter(Mandatory = $true)]
		[ValidatePattern('[\w+]')]
		[string] $ServiceName,

		[switch] $TryStart
	)

	Write-Verbose "Checking Service..."
	$s = Get-Service $ServiceName -ErrorAction SilentlyContinue
	if ($null -ne $s) {
		if ($s.Status -ne "Running") {
			Write-Verbose "$ServiceName service is not running."
			if ($TryStart) {
				Write-Verbose "Attempting to start $ServiceName..."
				Start-Service -Name $ServiceName -ErrorAction SilentlyContinue
				if ((Get-Service $ServiceName).Status -eq "Running") {
					Write-Verbose "$ServiceName service started."
					Start-Sleep 3
					return $true
				} else {
					Write-Error "Failed to start $ServiceName service."
					return $false
				}
			}
			return $false
		} else {
			Write-Verbose "$ServiceName is running."
			return $true
		}
	} else {
		Write-Verbose "Service Not Found."
		return $false
	}
}
