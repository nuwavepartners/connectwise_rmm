# Uninstall CW RMM
Write-Output ""
Write-Output "Beginning CW RMM Uninstall"

#Uninstall ITSPlatform Official Method
Start-Process -FilePath "C:\Program Files (x86)\ITSPlatform\agentcore\platform-agent-core.exe" -Wait -ArgumentList '"C:\Program Files (x86)\\ITSPlatform\config\platform_agent_core_cfg.json" "C:\Program Files (x86)\\ITSPlatformSetupLogs\platform_agent_core.log" uninstallagent'

# Uninstall ITSPlatform Fallback Method
Write-Output "Triggering ITSPlatform uninstall"
Get-WmiObject -Class Win32_Product -Filter "Name='ITSPlatform'" | ForEach-Object { $_.Uninstall() }

# Run Uninstall.exe for SAAZOD
Write-Output "Triggering SAAZOD uninstall"
if (Test-Path -Path "C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.exe") {
	Start-Process -FilePath "C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.exe" -Wait -ArgumentList '/silent /u:"C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.xml"'
	Start-Sleep -s 10
}
else {
	Write-Output "WARNING: C:\Program Files (x86)\SAAZOD\Uninstall\Uninstall.exe does not exist"
}


# Stop and force close related processes
#Get-Process -Name 'platform-agent*', 'SAAZ*', 'rthlpdk' | Stop-Process -Force
Write-Output "Stopping CW RMM processes"
$CWRMMProcesses = @(
	'platform-agent*',
	'platform-*-plugin',
	'SAAZ*',
	'rthlpdk'
)

$ProcessesToStop = Get-Process -Name $CWRMMProcesses | Select-Object -ExpandProperty Name
forEach ($ProcessToStop in $ProcessesToStop) {
	if (Get-Process -Name "$ProcessToStop" -ErrorAction 'SilentlyContinue') {
		Write-Output "Stopping Process: $ProcessToStop"
		Get-Process -Name "$ProcessToStop" -ErrorAction 'SilentlyContinue' | Stop-Process -Force
	}
}

# Stop and force close related services
#Get-Service -Name 'ITSPlatform*', 'SAAZ*' | Stop-Service -Force
Write-Output "Stopping CW RMM services"
$CWRMMServices = @(
	'ITSPlatform*',
	'SAAZ*'
)

$ServicesToStop = Get-Service -Name $CWRMMServices -ErrorAction 'SilentlyContinue' | Select-Object -ExpandProperty Name
forEach ($ServiceToStop in $ServicesToStop) {
	if (Get-Service -Name "$ServiceToStop") {
		Write-Output "Stopping Service: $ServiceToStop"
		Get-Service -Name "$ServiceToStop" | Stop-Service -Force
	}
}

# Delete specified services
Write-Output "Deleting CW RMM services"
foreach ($service in $ServicesToStop) {
	#sc.exe delete $service
	Write-Output "Deleting service: $service"
	Start-Process -FilePath "sc.exe" -ArgumentList "delete", $service -NoNewWindow -Wait
	Start-Sleep -Seconds 1
}

#Alternative service deletion
Get-CimInstance -ClassName win32_service | Where-Object { ($_.PathName -like 'ITSPlatform*') -or ($_.PathName -like 'SAAZ*') } | ForEach-Object { Invoke-CimMethod $_ -Name StopService; Remove-CimInstance $_ -Verbose -Confirm:$false }


$CWRMMUninstallProcessesToStop = @(
	'ITSPlatform*'
)

$ProcessesToStop = Get-Process -Name $CWRMMUninstallProcessesToStop | Select-Object -ExpandProperty Name
forEach ($ProcessToStop in $ProcessesToStop) {
	if (Get-Process -Name "$ProcessToStop" -ErrorAction 'SilentlyContinue') {
		Write-Output "Stopping Process: $ProcessToStop"
		Get-Process -Name "$ProcessToStop" -ErrorAction 'SilentlyContinue' | Stop-Process -Force
	}
}


# Delete specified folders
Write-Output "Deleting CW RMM related folders."
$FoldersToDelete = @(
	'C:\Program Files (x86)\ITSPlatformSetupLogs',
	'C:\Program Files (x86)\ITSPlatform',
	'C:\Program Files (x86)\SAAZOD',
	'C:\Program Files (x86)\SAAZODBKP',
	'C:\ProgramData\SAAZOD'
)

foreach ($folder in $FoldersToDelete) {
	if (Test-Path $folder) {
		Write-Output "Deleting folder: $folder"
		Get-ChildItem $folder -Recurse -Force -ErrorAction 'SilentlyContinue' | Remove-Item -Recurse -Force -Confirm:$false -Verbose
		Start-Sleep -Seconds 1
		Remove-Item -Path $folder -Recurse -Force -Confirm:$false -Verbose
	}
}


# Remove "C:\Program" file
Write-Output "Testing for rogue 'C:\Program' file"
if (Test-Path -LiteralPath "C:\Program" -PathType leaf) {
	Write-Output "Deleting rogue 'C:\Program' file"
	Remove-Item -LiteralPath "C:\Program" -Force -Confirm:$false -Verbose
}


# Remove registry keys
Write-Output "Deleting CW RMM registry keys"
$RegistryKeysToRemove = @(
	'HKLM:\SOFTWARE\WOW6432Node\SAAZOD',
	'HKLM:\SOFTWARE\WOW6432Node\ITSPlatform'
)

foreach ($RegistryKey in $RegistryKeysToRemove) {
	if (Test-Path -LiteralPath $RegistryKey) {
		Write-Output "Deleting registry key: $RegistryKey"
		Remove-Item -Path $RegistryKey -Recurse -Force -Confirm:$false -Verbose
	}
}

# Remove the registry key with spaces
$BlankRegistryKey = "HKLM:\SOFTWARE\WOW6432Node\  \ITSPlatform"

# Test if the specific registry key exists
if (Test-Path -LiteralPath $BlankRegistryKey) {
	Write-Output "Deleting registry key: $BlankRegistryKey"

	# Get parent key's path
	$parentKey = Split-Path $BlankRegistryKey -Parent

	try {
		# Delete the parent key recursively
		Remove-Item -Path $parentKey -Recurse -Force -Confirm:$false -Verbose -ErrorAction Stop
		Write-Output "Parent registry key deleted successfully."
	}
	catch {
		Write-Output "Failed to delete parent registry key: $_"
	}
}
else {
	Write-Output "Blank registry key not found. Nothing to delete."
}



### Clean up installer registry keys

# Define the path to start the search
$startPath = 'HKLM:\SOFTWARE\Classes\Installer\Products\'

# Define the target product name
$targetProductName = 'ITSPlatform'

# Function to search for keys with the specified product name
function Find-RegistryKeys {
	param (
		[string]$Path
	)

	# Get all subkeys
	$subKeys = Get-ChildItem -Path $Path -ErrorAction SilentlyContinue

	# Loop through each subkey
	foreach ($subKey in $subKeys) {
		# Get the value of the productName property
		$productName = (Get-ItemProperty -Path $subKey.PSPath -Name 'productName' -ErrorAction SilentlyContinue).productName

		# Check if the productName matches the target product name
		if ($productName -eq $targetProductName) {
			# Output the path of the matching key
			#Write-Output $subKey.PSPath
			[PSCustomObject]@{
				Path = $subKey.PSPath
				ProductName = $productName
			}
		}

		# Search for matching keys in the current subkey
		Find-RegistryKeys -Path $subKey.PSPath
	}
}

# Start the search
$ProductRegistryKeysToRemove = Find-RegistryKeys -Path $startPath

# Delete the found keys
if ($ProductRegistryKeysToRemove) {
    foreach ($ProductRegistryKeyToRemove in $ProductRegistryKeysToRemove) {
        if (Test-Path -LiteralPath $ProductRegistryKeyToRemove.Path) {
            Write-Output "Deleting registry key: $($ProductRegistryKeyToRemove.Path)"
            Remove-Item -Path $ProductRegistryKeyToRemove.Path -Recurse -Force -Confirm:$false -Verbose
        }
    }
}

Write-Output "Done! CW RMM should be successfully uninstalled and remnants removed"
# SIG # Begin signature block
# MII6oAYJKoZIhvcNAQcCoII6kTCCOo0CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCATFJOqVQMdE746
# 5lJGzzEi+cUMpiLxCQ9UKVHSJSfWQqCCItYwggXMMIIDtKADAgECAhBUmNLR1FsZ
# lUgTecgRwIeZMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29mdCBJZGVu
# dGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3JpdHkgMjAy
# MDAeFw0yMDA0MTYxODM2MTZaFw00NTA0MTYxODQ0NDBaMHcxCzAJBgNVBAYTAlVT
# MR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jv
# c29mdCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRo
# b3JpdHkgMjAyMDCCAiIwDQYJKoZIhvcNAQEBBQADggIPADCCAgoCggIBALORKgeD
# Bmf9np3gx8C3pOZCBH8Ppttf+9Va10Wg+3cL8IDzpm1aTXlT2KCGhFdFIMeiVPvH
# or+Kx24186IVxC9O40qFlkkN/76Z2BT2vCcH7kKbK/ULkgbk/WkTZaiRcvKYhOuD
# PQ7k13ESSCHLDe32R0m3m/nJxxe2hE//uKya13NnSYXjhr03QNAlhtTetcJtYmrV
# qXi8LW9J+eVsFBT9FMfTZRY33stuvF4pjf1imxUs1gXmuYkyM6Nix9fWUmcIxC70
# ViueC4fM7Ke0pqrrBc0ZV6U6CwQnHJFnni1iLS8evtrAIMsEGcoz+4m+mOJyoHI1
# vnnhnINv5G0Xb5DzPQCGdTiO0OBJmrvb0/gwytVXiGhNctO/bX9x2P29Da6SZEi3
# W295JrXNm5UhhNHvDzI9e1eM80UHTHzgXhgONXaLbZ7LNnSrBfjgc10yVpRnlyUK
# xjU9lJfnwUSLgP3B+PR0GeUw9gb7IVc+BhyLaxWGJ0l7gpPKWeh1R+g/OPTHU3mg
# trTiXFHvvV84wRPmeAyVWi7FQFkozA8kwOy6CXcjmTimthzax7ogttc32H83rwjj
# O3HbbnMbfZlysOSGM1l0tRYAe1BtxoYT2v3EOYI9JACaYNq6lMAFUSw0rFCZE4e7
# swWAsk0wAly4JoNdtGNz764jlU9gKL431VulAgMBAAGjVDBSMA4GA1UdDwEB/wQE
# AwIBhjAPBgNVHRMBAf8EBTADAQH/MB0GA1UdDgQWBBTIftJqhSobyhmYBAcnz1AQ
# T2ioojAQBgkrBgEEAYI3FQEEAwIBADANBgkqhkiG9w0BAQwFAAOCAgEAr2rd5hnn
# LZRDGU7L6VCVZKUDkQKL4jaAOxWiUsIWGbZqWl10QzD0m/9gdAmxIR6QFm3FJI9c
# Zohj9E/MffISTEAQiwGf2qnIrvKVG8+dBetJPnSgaFvlVixlHIJ+U9pW2UYXeZJF
# xBA2CFIpF8svpvJ+1Gkkih6PsHMNzBxKq7Kq7aeRYwFkIqgyuH4yKLNncy2RtNwx
# AQv3Rwqm8ddK7VZgxCwIo3tAsLx0J1KH1r6I3TeKiW5niB31yV2g/rarOoDXGpc8
# FzYiQR6sTdWD5jw4vU8w6VSp07YEwzJ2YbuwGMUrGLPAgNW3lbBeUU0i/OxYqujY
# lLSlLu2S3ucYfCFX3VVj979tzR/SpncocMfiWzpbCNJbTsgAlrPhgzavhgplXHT2
# 6ux6anSg8Evu75SjrFDyh+3XOjCDyft9V77l4/hByuVkrrOj7FjshZrM77nq81YY
# uVxzmq/FdxeDWds3GhhyVKVB0rYjdaNDmuV3fJZ5t0GNv+zcgKCf0Xd1WF81E+Al
# GmcLfc4l+gcK5GEh2NQc5QfGNpn0ltDGFf5Ozdeui53bFv0ExpK91IjmqaOqu/dk
# ODtfzAzQNb50GQOmxapMomE2gj4d8yu8l13bS3g7LfU772Aj6PXsCyM2la+YZr9T
# 03u4aUoqlmZpxJTG9F9urJh4iIAGXKKy7aIwggb/MIIE56ADAgECAhMzAAIwPQdL
# Ktz0k+GcAAAAAjA9MA0GCSqGSIb3DQEBDAUAMFoxCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJ
# RCBWZXJpZmllZCBDUyBFT0MgQ0EgMDIwHhcNMjUwMzI1MTQ0MzM3WhcNMjUwMzI4
# MTQ0MzM3WjB+MQswCQYDVQQGEwJVUzERMA8GA1UECBMITWljaGlnYW4xEjAQBgNV
# BAcTCUthbGFtYXpvbzEjMCEGA1UEChMaTnVXYXZlIFRlY2hub2xvZ3kgUGFydG5l
# cnMxIzAhBgNVBAMTGk51V2F2ZSBUZWNobm9sb2d5IFBhcnRuZXJzMIIBojANBgkq
# hkiG9w0BAQEFAAOCAY8AMIIBigKCAYEA6vt+2iw3wEHF0r7FQkE27vU5LReyk4jq
# eAFlAfsXOyh1l86dx78OdmL2Gta8genqN8gKsivFQYG/s6MorXC1tvbggHQlxlRf
# yV2kSFJvX0yPxknQ9rKw4lbSLIbyds/yhjh50RKXr92wA7ixdbFAlWngK03tXrv1
# CPshERWgW8O7Avh9d6qmbtm1yUgp8AyyQil6Dt0CIymz5y8n+cR1LAyXKGmNi07t
# j0H/LEbQaYKUtIPBD9LIY9AcpPTa7igcUzOUdOhDIHQ0T3VPyrvory2PdPbj+A1F
# DcEwjqVmptnjzdSRX6G74JWEL7sai6ycTJBYKXy/aFLGHq7YI1eTjCCMzY1hoT2Q
# T2PEb+m3n2gsKLkPhZMMBPnMNKhLCnIXG63oMcXc0sxsUzvgdKiUIpkWRt0d8vq6
# dkP0djY/Zq0m2b1Cv0M62wxw+GhHymwqZdevp+aR6URah2EBmxU5laFhpVU37k8h
# 36447C87fM2YAzOUpCgW+lvfopuBvPvbAgMBAAGjggIYMIICFDAMBgNVHRMBAf8E
# AjAAMA4GA1UdDwEB/wQEAwIHgDA7BgNVHSUENDAyBgorBgEEAYI3YQEABggrBgEF
# BQcDAwYaKwYBBAGCN2HukfNMg8bbxHSBjNbafbipvhswHQYDVR0OBBYEFJxNPNK8
# whblsY94Yj9CKK6qLcDGMB8GA1UdIwQYMBaAFGWfUc6FaH8vikWIqt2nMbseDQBe
# MGcGA1UdHwRgMF4wXKBaoFiGVmh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lv
# cHMvY3JsL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDUyUyMEVPQyUyMENB
# JTIwMDIuY3JsMIGlBggrBgEFBQcBAQSBmDCBlTBkBggrBgEFBQcwAoZYaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBJRCUy
# MFZlcmlmaWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDAyLmNydDAtBggrBgEFBQcwAYYh
# aHR0cDovL29uZW9jc3AubWljcm9zb2Z0LmNvbS9vY3NwMGYGA1UdIARfMF0wUQYM
# KwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAIBgZngQwBBAEwDQYJKoZI
# hvcNAQEMBQADggIBAAyyDzEqhAjvvSYBnK7On94LfkPFqT/ItMaflh9GXCg1yGBW
# mnFl/IvEnAMQ59JckOYmDTM2iSDYfkU1DgDYU1K7JsR237sE//Nsmn9A1OOjMlTV
# hgIikSwu9+VYnVGht15a4j/iMfF3zSFwZDqbHN7rwW12lbdlQlCVCSvdUYkJ7fbI
# oA8ZlZ8L2R/7y5XG+D2sDOqGaYoGjhs521r1HVh8LapaRH/w2Ao9GKgatxiszUaY
# sOsRi7bUlTCxWXXaKhTMFPOzV8FMLPWu/tDBitin16q3/EtwvVI38omQVMTmCPsj
# woWbWhIlzssSyz8KZppACrIfADQa6mGjIL6K1S6s2xtNMhDxIZI3x6Iuca+Xp/0e
# H5MXdcA+25yO/RhvAT4UtTLQ3GY5aKxex9+g/PcBxh09CxHh9xHiO33ZFjdSGqpR
# /SJtF4MYHsPgQQ6l8DDRs0jhD5kzBlCtZ3pnp2rmGY6TnuxcLW1rCDVbXce6vp8K
# LJR+eRisLmQmgjBSSLijEG8Tw42wfAXh5Rw/gywjdVyYair02lkPGemYF7srKGv9
# plfslpFxTV+s7ea31cxsCWoYzVsgBOv+sTOmG9qxnFmPYrYeBDCBQkvsfaeK3AK/
# p5dpm0AqXhYBieaN3+9zdaEwCpM0p6ogKJaV8L2tFxp07Siax2EzPqdq3OzrMIIG
# /zCCBOegAwIBAgITMwACMD0HSyrc9JPhnAAAAAIwPTANBgkqhkiG9w0BAQwFADBa
# MQswCQYDVQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMSsw
# KQYDVQQDEyJNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ1MgRU9DIENBIDAyMB4XDTI1
# MDMyNTE0NDMzN1oXDTI1MDMyODE0NDMzN1owfjELMAkGA1UEBhMCVVMxETAPBgNV
# BAgTCE1pY2hpZ2FuMRIwEAYDVQQHEwlLYWxhbWF6b28xIzAhBgNVBAoTGk51V2F2
# ZSBUZWNobm9sb2d5IFBhcnRuZXJzMSMwIQYDVQQDExpOdVdhdmUgVGVjaG5vbG9n
# eSBQYXJ0bmVyczCCAaIwDQYJKoZIhvcNAQEBBQADggGPADCCAYoCggGBAOr7ftos
# N8BBxdK+xUJBNu71OS0XspOI6ngBZQH7FzsodZfOnce/DnZi9hrWvIHp6jfICrIr
# xUGBv7OjKK1wtbb24IB0JcZUX8ldpEhSb19Mj8ZJ0PaysOJW0iyG8nbP8oY4edES
# l6/dsAO4sXWxQJVp4CtN7V679Qj7IREVoFvDuwL4fXeqpm7ZtclIKfAMskIpeg7d
# AiMps+cvJ/nEdSwMlyhpjYtO7Y9B/yxG0GmClLSDwQ/SyGPQHKT02u4oHFMzlHTo
# QyB0NE91T8q76K8tj3T24/gNRQ3BMI6lZqbZ483UkV+hu+CVhC+7GousnEyQWCl8
# v2hSxh6u2CNXk4wgjM2NYaE9kE9jxG/pt59oLCi5D4WTDAT5zDSoSwpyFxut6DHF
# 3NLMbFM74HSolCKZFkbdHfL6unZD9HY2P2atJtm9Qr9DOtsMcPhoR8psKmXXr6fm
# kelEWodhAZsVOZWhYaVVN+5PId+uOOwvO3zNmAMzlKQoFvpb36Kbgbz72wIDAQAB
# o4ICGDCCAhQwDAYDVR0TAQH/BAIwADAOBgNVHQ8BAf8EBAMCB4AwOwYDVR0lBDQw
# MgYKKwYBBAGCN2EBAAYIKwYBBQUHAwMGGisGAQQBgjdh7pHzTIPG28R0gYzW2n24
# qb4bMB0GA1UdDgQWBBScTTzSvMIW5bGPeGI/Qiiuqi3AxjAfBgNVHSMEGDAWgBRl
# n1HOhWh/L4pFiKrdpzG7Hg0AXjBnBgNVHR8EYDBeMFygWqBYhlZodHRwOi8vd3d3
# Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJRCUyMFZlcmlm
# aWVkJTIwQ1MlMjBFT0MlMjBDQSUyMDAyLmNybDCBpQYIKwYBBQUHAQEEgZgwgZUw
# ZAYIKwYBBQUHMAKGWGh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2Vy
# dHMvTWljcm9zb2Z0JTIwSUQlMjBWZXJpZmllZCUyMENTJTIwRU9DJTIwQ0ElMjAw
# Mi5jcnQwLQYIKwYBBQUHMAGGIWh0dHA6Ly9vbmVvY3NwLm1pY3Jvc29mdC5jb20v
# b2NzcDBmBgNVHSAEXzBdMFEGDCsGAQQBgjdMg30BATBBMD8GCCsGAQUFBwIBFjNo
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL0RvY3MvUmVwb3NpdG9yeS5o
# dG0wCAYGZ4EMAQQBMA0GCSqGSIb3DQEBDAUAA4ICAQAMsg8xKoQI770mAZyuzp/e
# C35Dxak/yLTGn5YfRlwoNchgVppxZfyLxJwDEOfSXJDmJg0zNokg2H5FNQ4A2FNS
# uybEdt+7BP/zbJp/QNTjozJU1YYCIpEsLvflWJ1RobdeWuI/4jHxd80hcGQ6mxze
# 68FtdpW3ZUJQlQkr3VGJCe32yKAPGZWfC9kf+8uVxvg9rAzqhmmKBo4bOdta9R1Y
# fC2qWkR/8NgKPRioGrcYrM1GmLDrEYu21JUwsVl12ioUzBTzs1fBTCz1rv7QwYrY
# p9eqt/xLcL1SN/KJkFTE5gj7I8KFm1oSJc7LEss/CmaaQAqyHwA0GuphoyC+itUu
# rNsbTTIQ8SGSN8eiLnGvl6f9Hh+TF3XAPtucjv0YbwE+FLUy0NxmOWisXsffoPz3
# AcYdPQsR4fcR4jt92RY3UhqqUf0ibReDGB7D4EEOpfAw0bNI4Q+ZMwZQrWd6Z6dq
# 5hmOk57sXC1tawg1W13Hur6fCiyUfnkYrC5kJoIwUki4oxBvE8ONsHwF4eUcP4Ms
# I3VcmGoq9NpZDxnpmBe7Kyhr/aZX7JaRcU1frO3mt9XMbAlqGM1bIATr/rEzphva
# sZxZj2K2HgQwgUJL7H2nitwCv6eXaZtAKl4WAYnmjd/vc3WhMAqTNKeqICiWlfC9
# rRcadO0omsdhMz6natzs6zCCB1owggVCoAMCAQICEzMAAAAF+3pcMhNh310AAAAA
# AAUwDQYJKoZIhvcNAQEMBQAwYzELMAkGA1UEBhMCVVMxHjAcBgNVBAoTFU1pY3Jv
# c29mdCBDb3Jwb3JhdGlvbjE0MDIGA1UEAxMrTWljcm9zb2Z0IElEIFZlcmlmaWVk
# IENvZGUgU2lnbmluZyBQQ0EgMjAyMTAeFw0yMTA0MTMxNzMxNTNaFw0yNjA0MTMx
# NzMxNTNaMFoxCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9y
# YXRpb24xKzApBgNVBAMTIk1pY3Jvc29mdCBJRCBWZXJpZmllZCBDUyBFT0MgQ0Eg
# MDIwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDSGpl8PzKQpMDoINta
# +yGYGkOgF/su/XfZFW5KpXBA7doAsuS5GedMihGYwajR8gxCu3BHpQcHTrF2o6QB
# +oHp7G5tdMe7jj524dQJ0TieCMQsFDKW4y5I6cdoR294hu3fU6EwRf/idCSmHj4C
# HR5HgfaxNGtUqYquU6hCWGJrvdCDZ0eiK1xfW5PW9bcqem30y3voftkdss2ykxku
# RYFpsoyXoF1pZldik8Z1L6pjzSANo0K8WrR3XRQy7vEd6wipelMNPdDcB47FLKVJ
# Nz/vg/eiD2Pc656YQVq4XMvnm3Uy+lp0SFCYPy4UzEW/+Jk6PC9x1jXOFqdUsvKm
# XPXf83NKhTdCOE92oAaFEjCH9gPOjeMJ1UmBZBGtbzc/epYUWTE2IwTaI7gi5iCP
# tHCx4bC/sj1zE7JoeKEox1P016hKOlI3NWcooZxgy050y0oWqhXsKKbabzgaYhhl
# MGitH8+j2LCVqxNgoWkZmp1YrJick7YVXygyZaQgrWJqAsuAS3plpHSuT/WNRiyz
# JOJGpavzhCzdcv9XkpQES1QRB9D/hG2cjT24UVQgYllX2YP/E5SSxah0asJBJ6bo
# fLbrXEwkAepOoy4MqDCLzGT+Z+WvvKFc8vvdI5Qua7UCq7gjsal7pDA1bZO1AHEz
# e+1JOZ09bqsrnLSAQPnVGOzIrQIDAQABo4ICDjCCAgowDgYDVR0PAQH/BAQDAgGG
# MBAGCSsGAQQBgjcVAQQDAgEAMB0GA1UdDgQWBBRln1HOhWh/L4pFiKrdpzG7Hg0A
# XjBUBgNVHSAETTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5t
# aWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBkGCSsGAQQB
# gjcUAgQMHgoAUwB1AGIAQwBBMBIGA1UdEwEB/wQIMAYBAf8CAQAwHwYDVR0jBBgw
# FoAU2UEpsA8PY2zvadf1zSmepEhqMOYwcAYDVR0fBGkwZzBloGOgYYZfaHR0cDov
# L3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jcmwvTWljcm9zb2Z0JTIwSUQlMjBW
# ZXJpZmllZCUyMENvZGUlMjBTaWduaW5nJTIwUENBJTIwMjAyMS5jcmwwga4GCCsG
# AQUFBwEBBIGhMIGeMG0GCCsGAQUFBzAChmFodHRwOi8vd3d3Lm1pY3Jvc29mdC5j
# b20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUyMElEJTIwVmVyaWZpZWQlMjBDb2Rl
# JTIwU2lnbmluZyUyMFBDQSUyMDIwMjEuY3J0MC0GCCsGAQUFBzABhiFodHRwOi8v
# b25lb2NzcC5taWNyb3NvZnQuY29tL29jc3AwDQYJKoZIhvcNAQEMBQADggIBAEVJ
# YNR3TxfiDkfO9V+sHVKJXymTpc8dP2M+QKa9T+68HOZlECNiTaAphHelehK1Elon
# +WGMLkOr/ZHs/VhFkcINjIrTO9JEx0TphC2AaOax2HMPScJLqFVVyB+Y1Cxw8nVY
# fFu8bkRCBhDRkQPUU3Qw49DNZ7XNsflVrR1LG2eh0FVGOfINgSbuw0Ry8kdMbd5f
# MDJ3TQTkoMKwSXjPk7Sa9erBofY9LTbTQTo/haovCCz82ZS7n4BrwvD/YSfZWQhb
# s+SKvhSfWMbr62P96G6qAXJQ88KHqRue+TjxuKyL/M+MBWSPuoSuvt9JggILMniz
# hhQ1VUeB2gWfbFtbtl8FPdAD3N+Gr27gTFdutUPmvFdJMURSDaDNCr0kfGx0fIx9
# wIosVA5c4NLNxh4ukJ36voZygMFOjI90pxyMLqYCrr7+GIwOem8pQgenJgTNZR5q
# 23Ipe0x/5Csl5D6fLmMEv7Gp0448TPd2Duqfz+imtStRsYsG/19abXx9Zd0C/U8K
# 0sv9pwwu0ejJ5JUwpBioMdvdCbS5D41DRgTiRTFJBr5b9wLNgAjfa43Sdv0zgyvW
# mPhslmJ02QzgnJip7OiEgvFiSAdtuglAhKtBaublFh3KEoGmm0n0kmfRnrcuN2fO
# U5TGOWwBtCKvZabP84kTvTcFseZBlHDM/HW+7tLnMIIHnjCCBYagAwIBAgITMwAA
# AAeHozSje6WOHAAAAAAABzANBgkqhkiG9w0BAQwFADB3MQswCQYDVQQGEwJVUzEe
# MBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMUgwRgYDVQQDEz9NaWNyb3Nv
# ZnQgSWRlbnRpdHkgVmVyaWZpY2F0aW9uIFJvb3QgQ2VydGlmaWNhdGUgQXV0aG9y
# aXR5IDIwMjAwHhcNMjEwNDAxMjAwNTIwWhcNMzYwNDAxMjAxNTIwWjBjMQswCQYD
# VQQGEwJVUzEeMBwGA1UEChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTQwMgYDVQQD
# EytNaWNyb3NvZnQgSUQgVmVyaWZpZWQgQ29kZSBTaWduaW5nIFBDQSAyMDIxMIIC
# IjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAsvDArxmIKOLdVHpMSWxpCFUJ
# tFL/ekr4weslKPdnF3cpTeuV8veqtmKVgok2rO0D05BpyvUDCg1wdsoEtuxACEGc
# gHfjPF/nZsOkg7c0mV8hpMT/GvB4uhDvWXMIeQPsDgCzUGzTvoi76YDpxDOxhgf8
# JuXWJzBDoLrmtThX01CE1TCCvH2sZD/+Hz3RDwl2MsvDSdX5rJDYVuR3bjaj2Qfz
# ZFmwfccTKqMAHlrz4B7ac8g9zyxlTpkTuJGtFnLBGasoOnn5NyYlf0xF9/bjVRo4
# Gzg2Yc7KR7yhTVNiuTGH5h4eB9ajm1OCShIyhrKqgOkc4smz6obxO+HxKeJ9bYmP
# f6KLXVNLz8UaeARo0BatvJ82sLr2gqlFBdj1sYfqOf00Qm/3B4XGFPDK/H04kteZ
# EZsBRc3VT2d/iVd7OTLpSH9yCORV3oIZQB/Qr4nD4YT/lWkhVtw2v2s0TnRJubL/
# hFMIQa86rcaGMhNsJrhysLNNMeBhiMezU1s5zpusf54qlYu2v5sZ5zL0KvBDLHtL
# 8F9gn6jOy3v7Jm0bbBHjrW5yQW7S36ALAt03QDpwW1JG1Hxu/FUXJbBO2AwwVG4F
# re+ZQ5Od8ouwt59FpBxVOBGfN4vN2m3fZx1gqn52GvaiBz6ozorgIEjn+PhUXILh
# AV5Q/ZgCJ0u2+ldFGjcCAwEAAaOCAjUwggIxMA4GA1UdDwEB/wQEAwIBhjAQBgkr
# BgEEAYI3FQEEAwIBADAdBgNVHQ4EFgQU2UEpsA8PY2zvadf1zSmepEhqMOYwVAYD
# VR0gBE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9z
# b2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAZBgkrBgEEAYI3FAIE
# DB4KAFMAdQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/MB8GA1UdIwQYMBaAFMh+0mqF
# KhvKGZgEByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmgd6B1hnNodHRwOi8vd3d3Lm1p
# Y3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3NvZnQlMjBJZGVudGl0eSUyMFZl
# cmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIw
# MjAuY3JsMIHDBggrBgEFBQcBAQSBtjCBszCBgQYIKwYBBQUHMAKGdWh0dHA6Ly93
# d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMvTWljcm9zb2Z0JTIwSWRlbnRp
# dHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2VydGlmaWNhdGUlMjBBdXRob3Jp
# dHklMjAyMDIwLmNydDAtBggrBgEFBQcwAYYhaHR0cDovL29uZW9jc3AubWljcm9z
# b2Z0LmNvbS9vY3NwMA0GCSqGSIb3DQEBDAUAA4ICAQB/JSqe/tSr6t1mCttXI0y6
# XmyQ41uGWzl9xw+WYhvOL47BV09Dgfnm/tU4ieeZ7NAR5bguorTCNr58HOcA1tcs
# HQqt0wJsdClsu8bpQD9e/al+lUgTUJEV80Xhco7xdgRrehbyhUf4pkeAhBEjABvI
# UpD2LKPho5Z4DPCT5/0TlK02nlPwUbv9URREhVYCtsDM+31OFU3fDV8BmQXv5hT2
# RurVsJHZgP4y26dJDVF+3pcbtvh7R6NEDuYHYihfmE2HdQRq5jRvLE1Eb59PYwIS
# FCX2DaLZ+zpU4bX0I16ntKq4poGOFaaKtjIA1vRElItaOKcwtc04CBrXSfyL2Op6
# mvNIxTk4OaswIkTXbFL81ZKGD+24uMCwo/pLNhn7VHLfnxlMVzHQVL+bHa9KhTyz
# wdG/L6uderJQn0cGpLQMStUuNDArxW2wF16QGZ1NtBWgKA8Kqv48M8HfFqNifN6+
# zt6J0GwzvU8g0rYGgTZR8zDEIJfeZxwWDHpSxB5FJ1VVU1LIAtB7o9PXbjXzGifa
# IMYTzU4YKt4vMNwwBmetQDHhdAtTPplOXrnI9SI6HeTtjDD3iUN/7ygbahmYOHk7
# VB7fwT4ze+ErCbMh6gHV1UuXPiLciloNxH6K4aMfZN1oLVk6YFeIJEokuPgNPa6E
# nTiOL60cPqfny+Fq8UiuZzGCFyAwghccAgEBMHEwWjELMAkGA1UEBhMCVVMxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjErMCkGA1UEAxMiTWljcm9zb2Z0
# IElEIFZlcmlmaWVkIENTIEVPQyBDQSAwMgITMwACMD0HSyrc9JPhnAAAAAIwPTAN
# BglghkgBZQMEAgEFAKBeMBAGCisGAQQBgjcCAQwxAjAAMBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMC8GCSqGSIb3DQEJBDEiBCCIA9EmaqsTwR1bPHCZ0IbrHM8r
# X7em7iLCz75Gy/ZSJzANBgkqhkiG9w0BAQEFAASCAYDlv2w+joYDH8JQzbp3MBRH
# o62LK49AcPjcS9R0TNvgvpHHgEf3liCiU1teM+wZCG2HEx3RLGHEPDtSt9xbc9ZV
# Jat0/HPI0RjsWv68rtyUG7ZmyWZoeXV+kjnlMfwsfF8gN2Ogy8b3tE7ApT+txzvx
# 9LOvZxEbXBAiEg+FT6WhINulErNdseCg8Ue1ho9cXG/EM5YT29gllhOskmUPepsp
# JdzZ8m+DcLlEitx8UPwUYRdtatOB1xFkNyyniH38Kz520w+kkmwIwmyAtS8TOpWC
# MJKogrfjmM53yvIjtLVnbPvmSTpRwZMYkPJoEH2k/y5w1LLp8i8i5borDCSp8eF+
# +I6DX1zQHpkEEqaCdnseY17H50SW3qCoCoBWckZsjVT5Jp3q8ZUvd2yZogaI9yxy
# bD4yaOQrjZIxCK5xe7sGYlQqiMREohZDUJ7DhDxcsXALiv/CTZXQrCKEiUwLFn+W
# O+YFGCgst5+Kao384A/T8ox0leiu7JJhaQXxeiiTfIahghSgMIIUnAYKKwYBBAGC
# NwMDATGCFIwwghSIBgkqhkiG9w0BBwKgghR5MIIUdQIBAzEPMA0GCWCGSAFlAwQC
# AQUAMIIBYQYLKoZIhvcNAQkQAQSgggFQBIIBTDCCAUgCAQEGCisGAQQBhFkKAwEw
# MTANBglghkgBZQMEAgEFAAQgYwrkZTCEKx0JgXCqEquaw6U29ieseK5sxh/2IiuC
# sxACBmfdnyoCkxgTMjAyNTAzMjYxNDIyNDEuMDU2WjAEgAIB9KCB4KSB3TCB2jEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBF
# U046RTQ2Mi05NkYwLTQ0MkUxNTAzBgNVBAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNB
# IFRpbWUgU3RhbXBpbmcgQXV0aG9yaXR5oIIPIDCCB4IwggVqoAMCAQICEzMAAAAF
# 5c8P/2YuyYcAAAAAAAUwDQYJKoZIhvcNAQEMBQAwdzELMAkGA1UEBhMCVVMxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjFIMEYGA1UEAxM/TWljcm9zb2Z0
# IElkZW50aXR5IFZlcmlmaWNhdGlvbiBSb290IENlcnRpZmljYXRlIEF1dGhvcml0
# eSAyMDIwMB4XDTIwMTExOTIwMzIzMVoXDTM1MTExOTIwNDIzMVowYTELMAkGA1UE
# BhMCVVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMp
# TWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwggIiMA0G
# CSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQCefOdSY/3gxZ8FfWO1BiKjHB7X55cz
# 0RMFvWVGR3eRwV1wb3+yq0OXDEqhUhxqoNv6iYWKjkMcLhEFxvJAeNcLAyT+XdM5
# i2CgGPGcb95WJLiw7HzLiBKrxmDj1EQB/mG5eEiRBEp7dDGzxKCnTYocDOcRr9Kx
# qHydajmEkzXHOeRGwU+7qt8Md5l4bVZrXAhK+WSk5CihNQsWbzT1nRliVDwunuLk
# X1hyIWXIArCfrKM3+RHh+Sq5RZ8aYyik2r8HxT+l2hmRllBvE2Wok6IEaAJanHr2
# 4qoqFM9WLeBUSudz+qL51HwDYyIDPSQ3SeHtKog0ZubDk4hELQSxnfVYXdTGncaB
# nB60QrEuazvcob9n4yR65pUNBCF5qeA4QwYnilBkfnmeAjRN3LVuLr0g0FXkqfYd
# Umj1fFFhH8k8YBozrEaXnsSL3kdTD01X+4LfIWOuFzTzuoslBrBILfHNj8RfOxPg
# juwNvE6YzauXi4orp4Sm6tF245DaFOSYbWFK5ZgG6cUY2/bUq3g3bQAqZt65Kcae
# wEJ3ZyNEobv35Nf6xN6FrA6jF9447+NHvCjeWLCQZ3M8lgeCcnnhTFtyQX3XgCoc
# 6IRXvFOcPVrr3D9RPHCMS6Ckg8wggTrtIVnY8yjbvGOUsAdZbeXUIQAWMs0d3cRD
# v09SvwVRd61evQIDAQABo4ICGzCCAhcwDgYDVR0PAQH/BAQDAgGGMBAGCSsGAQQB
# gjcVAQQDAgEAMB0GA1UdDgQWBBRraSg6NS9IY0DPe9ivSek+2T3bITBUBgNVHSAE
# TTBLMEkGBFUdIAAwQTA/BggrBgEFBQcCARYzaHR0cDovL3d3dy5taWNyb3NvZnQu
# Y29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRtMBMGA1UdJQQMMAoGCCsGAQUF
# BwMIMBkGCSsGAQQBgjcUAgQMHgoAUwB1AGIAQwBBMA8GA1UdEwEB/wQFMAMBAf8w
# HwYDVR0jBBgwFoAUyH7SaoUqG8oZmAQHJ89QEE9oqKIwgYQGA1UdHwR9MHsweaB3
# oHWGc2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY3JsL01pY3Jvc29m
# dCUyMElkZW50aXR5JTIwVmVyaWZpY2F0aW9uJTIwUm9vdCUyMENlcnRpZmljYXRl
# JTIwQXV0aG9yaXR5JTIwMjAyMC5jcmwwgZQGCCsGAQUFBwEBBIGHMIGEMIGBBggr
# BgEFBQcwAoZ1aHR0cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9N
# aWNyb3NvZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0
# aWZpY2F0ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3J0MA0GCSqGSIb3DQEBDAUAA4IC
# AQBfiHbHfm21WhV150x4aPpO4dhEmSUVpbixNDmv6TvuIHv1xIs174bNGO/ilWMm
# +Jx5boAXrJxagRhHQtiFprSjMktTliL4sKZyt2i+SXncM23gRezzsoOiBhv14YSd
# 1Klnlkzvgs29XNjT+c8hIfPRe9rvVCMPiH7zPZcw5nNjthDQ+zD563I1nUJ6y59T
# bXWsuyUsqw7wXZoGzZwijWT5oc6GvD3HDokJY401uhnj3ubBhbkR83RbfMvmzdp3
# he2bvIUztSOuFzRqrLfEvsPkVHYnvH1wtYyrt5vShiKheGpXa2AWpsod4OJyT4/y
# 0dggWi8g/tgbhmQlZqDUf3UqUQsZaLdIu/XSjgoZqDjamzCPJtOLi2hBwL+KsCh0
# Nbwc21f5xvPSwym0Ukr4o5sCcMUcSy6TEP7uMV8RX0eH/4JLEpGyae6Ki8JYg5v4
# fsNGif1OXHJ2IWG+7zyjTDfkmQ1snFOTgyEX8qBpefQbF0fx6URrYiarjmBprwP6
# ZObwtZXJ23jK3Fg/9uqM3j0P01nzVygTppBabzxPAh/hHhhls6kwo3QLJ6No803j
# UsZcd4JQxiYHHc+Q/wAMcPUnYKv/q2O444LO1+n6j01z5mggCSlRwD9faBIySAcA
# 9S8h22hIAcRQqIGEjolCK9F6nK9ZyX4lhthsGHumaABdWzCCB5YwggV+oAMCAQIC
# EzMAAABK/bhVx2KqyYkAAAAAAEowDQYJKoZIhvcNAQEMBQAwYTELMAkGA1UEBhMC
# VVMxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjEyMDAGA1UEAxMpTWlj
# cm9zb2Z0IFB1YmxpYyBSU0EgVGltZXN0YW1waW5nIENBIDIwMjAwHhcNMjQxMTI2
# MTg0ODU1WhcNMjUxMTE5MTg0ODU1WjCB2jELMAkGA1UEBhMCVVMxEzARBgNVBAgT
# Cldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1vbmQxHjAcBgNVBAoTFU1pY3Jvc29m
# dCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWljcm9zb2Z0IEFtZXJpY2EgT3BlcmF0
# aW9uczEmMCQGA1UECxMdVGhhbGVzIFRTUyBFU046RTQ2Mi05NkYwLTQ0MkUxNTAz
# BgNVBAMTLE1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWUgU3RhbXBpbmcgQXV0aG9y
# aXR5MIICIjANBgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEA6DkQYZ6zYlw1AbxF
# kFNwc0V0BaXCCo1/+d01YKizalK9bX8fGrIUSVf75pYJOrhYmofIMh7wBv8j+kIp
# lOKYixrtVq+aQwAezI0wBFdFFeOyNCIynTQwz343z5IWVZ0/7cOXT1IDk9fIsI51
# kZKHa4SPf9rFmH9XtH1/P1ExueAGskBF/AvI1Ol2Vv2W9EDke8csxcPgXTkDNG9I
# 5ljEjM9pZUzf9kgw8Po8CVpD1/OFb468jcaWpsi/ydqboa3KJnPoyUlnq+cmgp6f
# kpqYmPM3EhAr1aAqbMnkiUrD4Q15DTv0XoZOi1zjXRhF5xxXKLr1m5k5xZlHp7mn
# PimiG67T7/e5DuFFt7XbAsOCW8N1Zq5jdNeLrMLtBvkRyKlkTSsp6nJQXR4Rf2e8
# 7TrveQiJjLsW+ZQ46KXdcDI1WoaxI0JzypicOQBbcU98823p/TArYdVpIYuYlXq0
# 923cf9+im62BVFG9eXhm+601RsXdWlH7QUMZzbD233aAP8LiB0pDrkK/ybUpYs6D
# okAJ9r0am4NFXu7LC+DfIFveRIZOCBaHGt4SJ3G2VgkFIoALFcThj+ro7oX+BT3s
# r0L57Lzi/QmU2UkTCwV1qKM6+aqbzhV4BxsxRjfQdetqzFvxI4IHf0IBuPoYYMiJ
# 4AXTa2moymfuejK2NZgL75mWwisCAwEAAaOCAcswggHHMB0GA1UdDgQWBBQXdNaJ
# ti4We46ErU/TNnIOeWGVejAfBgNVHSMEGDAWgBRraSg6NS9IY0DPe9ivSek+2T3b
# ITBsBgNVHR8EZTBjMGGgX6BdhltodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtp
# b3BzL2NybC9NaWNyb3NvZnQlMjBQdWJsaWMlMjBSU0ElMjBUaW1lc3RhbXBpbmcl
# MjBDQSUyMDIwMjAuY3JsMHkGCCsGAQUFBwEBBG0wazBpBggrBgEFBQcwAoZdaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9jZXJ0cy9NaWNyb3NvZnQlMjBQ
# dWJsaWMlMjBSU0ElMjBUaW1lc3RhbXBpbmclMjBDQSUyMDIwMjAuY3J0MAwGA1Ud
# EwEB/wQCMAAwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwgwDgYDVR0PAQH/BAQDAgeA
# MGYGA1UdIARfMF0wUQYMKwYBBAGCN0yDfQEBMEEwPwYIKwYBBQUHAgEWM2h0dHA6
# Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTAI
# BgZngQwBBAIwDQYJKoZIhvcNAQEMBQADggIBADApzTDXWbyj/r85v6Az19sJPtwK
# dE5ukA0FrPxJffIDQ0WJLW1G7zXIXIJY3S5dCHbvXr5bDrmL67MlnU0M0RIapm5x
# pS8ejuWdRplHqkRiwhB5hm+7nEdxm+YdKCcoIPxbGqI1t8E0S0Zt7uw1/9LzRUar
# duTHQ0PKyZQnuYkHLGx83/+RR40w1gemiIFtC/UfvNY9URHCfB6bWp90qi3TjWLM
# O03FwcpuvZ15RubMVH/eH3WavJjLB4rDWd7NzeSAkiTqCEUAFNqrGFbnjOviBMUb
# KkAa/mFj9m1Dk6Zx4SbXtT5wCodX3k30m0cSB2nClULbR4YyWO5/MoSlTwnMPvFX
# MOWUkzd/SARbw7XVF6WLtgZHVBKAyZ4MFKwrKCP8hXdozdkeOX3Ru12+wewRk8An
# o/f9zrm4G/B/wO6u7smB3eR8OerqioPt73ufFMWsSCwXhSGz8xpjq6DKiG39sDRP
# F2CHnsBIJmv7dPMgYCKxskb7GiIkHbqa79vIAqQs9nY4s7XhR8NKRAKVIYj9/8Xk
# eY5S1G0YQhCwQlRUtvHZMY0pYmOXBfWpjQG+ZaIwfd07tB0hprJBh5zJLIussfsI
# P3tGr4o64tqRa8+OItP3mLWCdslKcBY5HIzHC2b0NnasAY1bqzfTfotsflhrV+pX
# SyN3As36dKMTqpGGMYID1DCCA9ACAQEweDBhMQswCQYDVQQGEwJVUzEeMBwGA1UE
# ChMVTWljcm9zb2Z0IENvcnBvcmF0aW9uMTIwMAYDVQQDEylNaWNyb3NvZnQgUHVi
# bGljIFJTQSBUaW1lc3RhbXBpbmcgQ0EgMjAyMAITMwAAAEr9uFXHYqrJiQAAAAAA
# SjANBglghkgBZQMEAgEFAKCCAS0wGgYJKoZIhvcNAQkDMQ0GCyqGSIb3DQEJEAEE
# MC8GCSqGSIb3DQEJBDEiBCAaOeCJZ7vgX08Kr8lL7VYomtzcO13WnoAXqPuPv9Xs
# UDCB3QYLKoZIhvcNAQkQAi8xgc0wgcowgccwgaAEIGZ7KbWlzY0AQkdLdW/gAxiy
# l7PEf9Wpsv+xde8uw+EKMHwwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQKExVN
# aWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJsaWMg
# UlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAASv24VcdiqsmJAAAAAABKMCIE
# IDGkEAaCtO4x4SwgCSnySTWuobK0xnVpZUbgzGzVKPUQMA0GCSqGSIb3DQEBCwUA
# BIICADPnHI801HNqhPQCZE3gij/TRGRyYqDo3T02R8uwJPtRJREQ6zK2cuKC1AKR
# b/RWQFIu0JZQXHpjd4rbNACTsZGg31J7kQZ/TTjNj/t40ws5FiUtHcZTHNuR3uMx
# BQRMhmNwy2YaOTkd3ifg5nKuX/KFnMNbXq6h+42QJgpRYW7ubFnfVrffbIzWn+18
# mw/181AwLIcGpm25ZTCNUyAqrksfGj0vkB6T0KcuX2gSooY+MoZ2VUEDdnSjmKnq
# N4vIvquP2edJr1mtYCmoUtYibZWDZerQKHdjcvWm5FEHZnwWevRd5VnWIN+WujAI
# NupbPrqj+pqCfzz8uMw6SgsE6RKPTNDnJN/JrK4HHmn10hPiLhdI+jibMDIECFYk
# Mihq55YSbEVGKLPjzcGBd2b0c/l7REbucqjweXrdNUb94vY2nLi0BGrm612nVPuE
# b6ftievDVy+Yn74Iu6xbr1I4Q/Y7mtYJ/rivmjwYPr3mO/j0o31ciwAxzPedxr5R
# ZICnrnLHev0BXerawdAaeoDJOjKGF6M+AdWNa4WnCBTOQKk/dAYSjc71hsJ3fC+Q
# rYw0CNkDkLF50WB2U6EpSEmLXeb3YNwZXCLdH22lZt0R7PCfk/XlKb+u3nlVaNyr
# kn+d1p4kJ2PKHMCr2Cl91VVFRtmUGGxyQ6hzJaemiyTw8guT
# SIG # End signature block
