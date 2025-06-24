function Invoke-StatusCheck {
	$ITSStatusFile = 'C:\Program Files (x86)\ITSPlatform\log\agent_health.json'
	if (Test-Path -Path $ITSStatusFile -PathType Leaf) {
		$ITSStatus = Get-Content -Path $ITSStatusFile | ConvertFrom-Json
		if ($ITSStatus.agentCore.heartbeatStatus.timestampUTC -gt (Get-Date).AddMinutes(-30)) {
			Write-Verbose 'ITS Core Heartbeat Good'
		} else { return $false }
	} else { return $false }

	$SAAZStatusFile = 'C:\Program Files (x86)\SAAZOD\SAAZServiceCheck.INI'
	if (Test-Path -Path $SAAZStatusFile -PathType Leaf) {
		$SAAZStatus = Get-IniContent $SAAZStatusFile
		foreach ($SAAZServ in $SAAZStatus.Keys) {
			if ($SAAZStatus.$SAAZServ.RTime -gt (Get-Date).AddMinutes(-30)) {
				Write-Verbose "$SAAZServ Checkin Good"
			} else { return $false }
		}
	} else { return $false }

	return $true
}
