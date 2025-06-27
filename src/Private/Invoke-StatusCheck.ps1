function Invoke-StatusCheck {


	function Get-IniContent {
		[CmdletBinding()]
		param (
			[Parameter(Mandatory = $true, ValueFromPipeline = $true, Position = 0)]
			[string]$FilePath
		)

		Begin {
			$signature = @"
// Gets all keys and values in a section.
[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
public static extern int GetPrivateProfileSection(
string lpAppName,
byte[] lpReturnedString,
int nSize,
string lpFileName
);

// Gets all section names.
[DllImport("kernel32.dll", CharSet = CharSet.Ansi, SetLastError = true)]
public static extern int GetPrivateProfileSectionNames(
byte[] lpszReturnBuffer,
int nSize,
string lpFileName
);
"@

			# Add the type to the current session if it doesn't already exist.
			if (-not ("Win32.IniReader" -as [type])) {
				Add-Type -MemberDefinition $signature -Name "IniReader" -Namespace "Win32"
			}
		}

		Process {
			$absolutePath = Resolve-Path -Path $FilePath
			$bufferSize = 32768

			# --- Get Section Names ---
			$sectionNamesBuffer = New-Object byte[] $bufferSize
			$bytesRead = [Win32.IniReader]::GetPrivateProfileSectionNames($sectionNamesBuffer, $bufferSize, $absolutePath)
			if ($bytesRead -eq 0) {
				Write-Warning "Could not read from INI file or the file is empty: $absolutePath"
				return $null
			}
			$allSections = ([System.Text.Encoding]::Ascii).GetString($sectionNamesBuffer, 0, $bytesRead).TrimEnd([char]0).Split([char]0)

			# --- Process Each Section ---
			$iniHashtable = [ordered]@{}
			foreach ($sectionName in $allSections) {
				$sectionBuffer = New-Object byte[] $bufferSize
				$sectionBytesRead = [Win32.IniReader]::GetPrivateProfileSection($sectionName, $sectionBuffer, $bufferSize, $absolutePath)

				$keyPairs = ([System.Text.Encoding]::Ascii).GetString($sectionBuffer, 0, $sectionBytesRead).TrimEnd([char]0).Split([char]0)

				$sectionHashtable = [ordered]@{}
				foreach ($keyPair in $keyPairs) {
					$parts = $keyPair.Split('=', 2)
					if ($parts.Length -eq 2) {
						$sectionHashtable[$parts[0]] = $parts[1]
					}
				}
				$iniHashtable[$sectionName] = $sectionHashtable
			}

			return $iniHashtable
		}
	}


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
