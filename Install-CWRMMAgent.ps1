<#
.NOTES
    Author:         Chris Stone <chris.stone@nuwavepartners.com>
    Date-Modified:  2025-03-20 14:48:55

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

	[switch] $SkipServiceCheck
)

###################################################################### FUNCTIONS

function Invoke-ServiceCheck {
	param(
		[Parameter(Mandatory = $true)]
		[string] $Service,
		[switch] $TryStart
	)

	Write-Output "Checking Service..."
	if (Get-Service $AgentService -ErrorAction SilentlyContinue) {
		if ((Get-Service $AgentService).Status -ne "Running") {
			Write-Output "$AgentService service is not running."
			if ($TryStart) {
				Write-Output "Attempting to start $AgentService..."
				Start-Service -Name $AgentService -ErrorAction SilentlyContinue
				if ((Get-Service $AgentService).Status -eq "Running") {
					Write-Output "$AgentService service started."
					Start-Sleep 3
					return $true
				} else {
					Write-Error "Failed to start $AgentService service."
					return $false
				}
			}
			return $false
		} else {
			Write-Output "$AgentService is running."
			return $true
		}
	} else {
		Write-Output "Service Not Found."
		return $false
	}
}

function Invoke-StatusCheck {
	$ITSStatusFile = 'C:\Program Files (x86)\ITSPlatform\log\agent_health.json'
	if (Test-Path -Path $ITSStatusFile -PathType Leaf) {
		$ITSStatus = Get-Content -Path $ITSStatusFile | ConvertFrom-Json
		if ($ITSStatus.agentCore.heartbeatStatus.timestampUTC -gt (Get-Date).AddMinutes(-30)) {
			Write-Output 'ITS Core Heartbeat Good'
		} else { return $false }
	} else { return $false }

	$SAAZStatusFile = 'C:\Program Files (x86)\SAAZOD\SAAZServiceCheck.INI'
	if (Test-Path -Path $SAAZStatusFile -PathType Leaf) {
		$SAAZStatus = Get-IniContent $SAAZStatusFile
		foreach ($SAAZServ in $SAAZStatus.Keys) {
			if ($SAAZStatus.$SAAZServ.RTime -gt (Get-Date).AddMinutes(-30)) {
				Write-Output "$SAAZServ Checkin Good"
			} else { return $false }
		}
	} else { return $false }

	return $true
}

function Invoke-EnvironmentCheck {
	Write-Output "Checking TLS Protocols"
	[Net.ServicePointManager]::SecurityProtocol = [System.Enum]::GetValues([System.Net.SecurityProtocolType]) | Where-Object { $_ -match 'Tls' };

	Write-Output "Checking Execution Policy"
	if (@('Unrestricted', 'RemoteSigned', 'Bypass') -notcontains (Get-ExecutionPolicy -Scope Process)) {
		Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
	}

	Write-Output "Checking NuGet and PowerShell Gallery"
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

	Write-Output "Checking PowerShell Modules"
	$requiredModules = @{
		"PS-WindowsInstaller" = [version]"1.2"
		"PsIni"               = [version]"3.1.2"
	}
	foreach ($moduleName in $requiredModules.Keys) {
		$requiredVersion = $requiredModules[$moduleName]
		Write-Output "Checking $moduleName module..."
		$module = Get-Module $moduleName -ListAvailable
		if (-not $module) {
			Write-Output "$moduleName module not found. Installing..."
			if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
				Install-Module $moduleName -Force -Scope AllUsers
			} else {
				Install-Module $moduleName -Force -Scope CurrentUser
			}
		} elseif ($module.Version -lt $requiredVersion) {
			Write-Output "$moduleName module version $($module.Version) is less than $($requiredVersion). Updating..."
			Update-Module $moduleName -Force
		} else {
			Write-Output "$moduleName module version $($module.Version) is $($requiredVersion) or higher."
		}
		Import-Module $moduleName -Force
		Write-Output "$moduleName module loaded."
	}
}

function Install-AgentMsi {
	param(
		[string] $MSIPath,
		[string] $Token
	)
	Write-Output "Installing $MSIPath"
	$installer = New-WindowsInstallerInstaller
	Set-WindowsInstallerInstallerUILevel -UILevel 2 -Installer $installer
	$session = Open-WindowsInstallerPackage -PackagePath $MSIPath
	Set-WindowsInstallerSessionProperty -Session $session -PropertyName 'TOKEN' -PropertyValue $Token
	Invoke-WindowsInstallerSessionAction -Session $session -Action 'INSTALL'
}

function Repair-AgentMsi {

}

#################################################################### MAIN SCRIPT

Start-Transcript -Path (Join-Path $env:TEMP ("NuWave_{0}.log" -f (Get-Date -Format "s")))
Write-Output ('Script Started ').PadRight(80, '-')

# if (!$PSBoundParameters.ContainsKey('SkipServiceCheck')) {
# 	if (Invoke-ServiceCheck -Service 'ITSPlatform') {
# 		Write-Output 'ITSPlatform Service Running Already'
# 		Exit 0
# 	}
# }

if (!$PSBoundParameters.ContainsKey('SkipStatusCheck')) {
	if (Invoke-StatusCheck) {
		Write-Output 'Status Check Working'
		Write-Output ('Script Finished ').PadRight(80, '-')
		Stop-Transcript
		Exit 0
	}
}

Invoke-EnvironmentCheck

$MSIPath = "$env:TEMP\agent.msi"
if (Test-Path -Path $MSIPath) { Remove-Item -Path $MSIPath -Force }
Invoke-WebRequest -Uri $AgentUri -OutFile $MSIPath
Install-AgentMsi -MSIPath $MSIPath -Token $Token
Remove-Item -Path $MSIPath

Write-Output ('Script Finished ').PadRight(80, '-')
Stop-Transcript

# SIG # Begin signature block
# MII+EQYJKoZIhvcNAQcCoII+AjCCPf4CAQExDzANBglghkgBZQMEAgEFADB5Bgor
# BgEEAYI3AgEEoGswaTA0BgorBgEEAYI3AgEeMCYCAwEAAAQQH8w7YFlLCE63JNLG
# KX7zUQIBAAIBAAIBAAIBAAIBADAxMA0GCWCGSAFlAwQCAQUABCAZ7lE8fML2TiaI
# AAkGlwCFv8jZlf9iC6XLsnd3x9aHxKCCItYwggXMMIIDtKADAgECAhBUmNLR1FsZ
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
# nTiOL60cPqfny+Fq8UiuZzGCGpEwghqNAgEBMHEwWjELMAkGA1UEBhMCVVMxHjAc
# BgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjErMCkGA1UEAxMiTWljcm9zb2Z0
# IElEIFZlcmlmaWVkIENTIEVPQyBDQSAwMgITMwACMD0HSyrc9JPhnAAAAAIwPTAN
# BglghkgBZQMEAgEFAKBeMBAGCisGAQQBgjcCAQwxAjAAMBkGCSqGSIb3DQEJAzEM
# BgorBgEEAYI3AgEEMC8GCSqGSIb3DQEJBDEiBCCUhwVILNiOR2T9x+0vdDQZFOF6
# oH7wlzbCYtVE0JzORTANBgkqhkiG9w0BAQEFAASCAYAT/JTZbMsCAFVvhUR3U8kb
# BMwPJLcnoMxXGSH+aROnZ+dQbdmE1LL84ynv+hlM3OsSiCtiVEySBaqjuChcvgu+
# yuZ9QTP459gdFzMVlpaVerQ26WQVL3t5V1UXs5mVLsPQMJmFb1SYMUkHFFzEK+i1
# ucFqSE/J7k5YVzuzHEgTbghTP9ELi07MnvMrFnlrJ1W3i2r4JRCwTU1oHYNdS6ar
# eNm8JWnEna/QHWSlgguQpZ87BsVVH7Cc276i2nqf5eoGmR59QXXcX8OoCohzBwo/
# t6KXZy/KDqLgtpu+8f/fJczZXHHlJa0bED2K1QlH+ON8efyKVrsS5rC1fdl861W5
# FKpHMcOYD00o7oM2zwKmycLMTto9zIISlPrAoH/ls2fqp8RTOpstwUF3SEp3bX/M
# Ryf9ymoIigA7U0grP0l4vyLPqFBt2cZ+dtm3PeMEeAOsoNgnJTCS5S0smWPGw8QO
# sJYf9HY5z/CILSN7cYNWgkqzkR0uOtyL0b1csAoCmoGhghgRMIIYDQYKKwYBBAGC
# NwMDATGCF/0wghf5BgkqhkiG9w0BBwKgghfqMIIX5gIBAzEPMA0GCWCGSAFlAwQC
# AQUAMIIBYgYLKoZIhvcNAQkQAQSgggFRBIIBTTCCAUkCAQEGCisGAQQBhFkKAwEw
# MTANBglghkgBZQMEAgEFAAQgsxIB0uDzvot1LabAp2BxrlyVJYFir1JgHBUpdS5w
# pV8CBmfdoMXgyhgTMjAyNTAzMjYxNDIyMzYuMjA3WjAEgAIB9KCB4aSB3jCB2zEL
# MAkGA1UEBhMCVVMxEzARBgNVBAgTCldhc2hpbmd0b24xEDAOBgNVBAcTB1JlZG1v
# bmQxHjAcBgNVBAoTFU1pY3Jvc29mdCBDb3Jwb3JhdGlvbjElMCMGA1UECxMcTWlj
# cm9zb2Z0IEFtZXJpY2EgT3BlcmF0aW9uczEnMCUGA1UECxMeblNoaWVsZCBUU1Mg
# RVNOOjc4MDAtMDVFMC1EOTQ3MTUwMwYDVQQDEyxNaWNyb3NvZnQgUHVibGljIFJT
# QSBUaW1lIFN0YW1waW5nIEF1dGhvcml0eaCCDyEwggeCMIIFaqADAgECAhMzAAAA
# BeXPD/9mLsmHAAAAAAAFMA0GCSqGSIb3DQEBDAUAMHcxCzAJBgNVBAYTAlVTMR4w
# HAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xSDBGBgNVBAMTP01pY3Jvc29m
# dCBJZGVudGl0eSBWZXJpZmljYXRpb24gUm9vdCBDZXJ0aWZpY2F0ZSBBdXRob3Jp
# dHkgMjAyMDAeFw0yMDExMTkyMDMyMzFaFw0zNTExMTkyMDQyMzFaMGExCzAJBgNV
# BAYTAlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMT
# KU1pY3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMIICIjAN
# BgkqhkiG9w0BAQEFAAOCAg8AMIICCgKCAgEAnnznUmP94MWfBX1jtQYioxwe1+eX
# M9ETBb1lRkd3kcFdcG9/sqtDlwxKoVIcaqDb+omFio5DHC4RBcbyQHjXCwMk/l3T
# OYtgoBjxnG/eViS4sOx8y4gSq8Zg49REAf5huXhIkQRKe3Qxs8Sgp02KHAznEa/S
# sah8nWo5hJM1xznkRsFPu6rfDHeZeG1Wa1wISvlkpOQooTULFm809Z0ZYlQ8Lp7i
# 5F9YciFlyAKwn6yjN/kR4fkquUWfGmMopNq/B8U/pdoZkZZQbxNlqJOiBGgCWpx6
# 9uKqKhTPVi3gVErnc/qi+dR8A2MiAz0kN0nh7SqINGbmw5OIRC0EsZ31WF3Uxp3G
# gZwetEKxLms73KG/Z+MkeuaVDQQheangOEMGJ4pQZH55ngI0Tdy1bi69INBV5Kn2
# HVJo9XxRYR/JPGAaM6xGl57Ei95HUw9NV/uC3yFjrhc087qLJQawSC3xzY/EXzsT
# 4I7sDbxOmM2rl4uKK6eEpurRduOQ2hTkmG1hSuWYBunFGNv21Kt4N20AKmbeuSnG
# nsBCd2cjRKG79+TX+sTehawOoxfeOO/jR7wo3liwkGdzPJYHgnJ54UxbckF914Aq
# HOiEV7xTnD1a69w/UTxwjEugpIPMIIE67SFZ2PMo27xjlLAHWW3l1CEAFjLNHd3E
# Q79PUr8FUXetXr0CAwEAAaOCAhswggIXMA4GA1UdDwEB/wQEAwIBhjAQBgkrBgEE
# AYI3FQEEAwIBADAdBgNVHQ4EFgQUa2koOjUvSGNAz3vYr0npPtk92yEwVAYDVR0g
# BE0wSzBJBgRVHSAAMEEwPwYIKwYBBQUHAgEWM2h0dHA6Ly93d3cubWljcm9zb2Z0
# LmNvbS9wa2lvcHMvRG9jcy9SZXBvc2l0b3J5Lmh0bTATBgNVHSUEDDAKBggrBgEF
# BQcDCDAZBgkrBgEEAYI3FAIEDB4KAFMAdQBiAEMAQTAPBgNVHRMBAf8EBTADAQH/
# MB8GA1UdIwQYMBaAFMh+0mqFKhvKGZgEByfPUBBPaKiiMIGEBgNVHR8EfTB7MHmg
# d6B1hnNodHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NybC9NaWNyb3Nv
# ZnQlMjBJZGVudGl0eSUyMFZlcmlmaWNhdGlvbiUyMFJvb3QlMjBDZXJ0aWZpY2F0
# ZSUyMEF1dGhvcml0eSUyMDIwMjAuY3JsMIGUBggrBgEFBQcBAQSBhzCBhDCBgQYI
# KwYBBQUHMAKGdWh0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9wa2lvcHMvY2VydHMv
# TWljcm9zb2Z0JTIwSWRlbnRpdHklMjBWZXJpZmljYXRpb24lMjBSb290JTIwQ2Vy
# dGlmaWNhdGUlMjBBdXRob3JpdHklMjAyMDIwLmNydDANBgkqhkiG9w0BAQwFAAOC
# AgEAX4h2x35ttVoVdedMeGj6TuHYRJklFaW4sTQ5r+k77iB79cSLNe+GzRjv4pVj
# JviceW6AF6ycWoEYR0LYhaa0ozJLU5Yi+LCmcrdovkl53DNt4EXs87KDogYb9eGE
# ndSpZ5ZM74LNvVzY0/nPISHz0Xva71QjD4h+8z2XMOZzY7YQ0Psw+etyNZ1Cesuf
# U211rLslLKsO8F2aBs2cIo1k+aHOhrw9xw6JCWONNboZ497mwYW5EfN0W3zL5s3a
# d4Xtm7yFM7Ujrhc0aqy3xL7D5FR2J7x9cLWMq7eb0oYioXhqV2tgFqbKHeDick+P
# 8tHYIFovIP7YG4ZkJWag1H91KlELGWi3SLv10o4KGag42pswjybTi4toQcC/irAo
# dDW8HNtX+cbz0sMptFJK+KObAnDFHEsukxD+7jFfEV9Hh/+CSxKRsmnuiovCWIOb
# +H7DRon9TlxydiFhvu88o0w35JkNbJxTk4MhF/KgaXn0GxdH8elEa2Imq45gaa8D
# +mTm8LWVydt4ytxYP/bqjN49D9NZ81coE6aQWm88TwIf4R4YZbOpMKN0CyejaPNN
# 41LGXHeCUMYmBx3PkP8ADHD1J2Cr/6tjuOOCztfp+o9Nc+ZoIAkpUcA/X2gSMkgH
# APUvIdtoSAHEUKiBhI6JQivRepyvWcl+JYbYbBh7pmgAXVswggeXMIIFf6ADAgEC
# AhMzAAAATBtLnGPC5NN6AAAAAABMMA0GCSqGSIb3DQEBDAUAMGExCzAJBgNVBAYT
# AlVTMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1p
# Y3Jvc29mdCBQdWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMB4XDTI0MTEy
# NjE4NDg1OVoXDTI1MTExOTE4NDg1OVowgdsxCzAJBgNVBAYTAlVTMRMwEQYDVQQI
# EwpXYXNoaW5ndG9uMRAwDgYDVQQHEwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3Nv
# ZnQgQ29ycG9yYXRpb24xJTAjBgNVBAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJh
# dGlvbnMxJzAlBgNVBAsTHm5TaGllbGQgVFNTIEVTTjo3ODAwLTA1RTAtRDk0NzE1
# MDMGA1UEAxMsTWljcm9zb2Z0IFB1YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRo
# b3JpdHkwggIiMA0GCSqGSIb3DQEBAQUAA4ICDwAwggIKAoICAQDcde8XEX4HjETY
# u6YHtWiP7+6Vf2abeUo/si4NcaeiKrRMTF8F7mpCoPJyo/h5VHbhyKDZazOm1cLu
# zKeVEMzDN4vuf3fZb5hSlpVlCXBSJ3YBLwLnRJtWNk+XkUMcAc96RdalToVYWltO
# IwbCCkjE42fnCafwjZajw1UGaxl4tRQNHwVk5gwC2wlVVSJREJqCSsB9TXXHIKxP
# HnnFJqJ/LI1goJ+Ve0Bar4PiKiMfnvnZ8LR3ktW24X6FDQJRKLjnJQ0JVebQEvI+
# q8Y/frheUldXeLVD4SfQNl1fLKN58o+NJsWI0ET6C8wYZc+eu+EqrzubIPXB7mKI
# 9cbtmGHvztslz1K/NmRvGGQkeKEKdOWfpfRuYxmhmeVmR1QMLe5pBccJiXw7PUIW
# +3MB0pM5SBF5FH6INtT1gf5vHwBA9vbeiiggbijJMuK0qu63sIbbE/YN4iYrCURv
# jZampsTtxmlEtN921N0qXNtNgU0vavdc/vJl/rDef6fMeQuJAinIHxcJzPDTsOXZ
# legwcCr/J52eij6T9szMlPSCQVAt5u/agNcJ212t6qdwZ4hYYF4LkCmXQgDPZpR1
# lGDCaojAB6zy/H7nME+nnTvTgTMtR4d4lHVBQxpJDnvYNvGPurrnP7FZT3ue8Yzf
# FEiE5chmJia8THexs46F8tCr8T5UxQIDAQABo4IByzCCAccwHQYDVR0OBBYEFGrq
# I3Sxu357rKTylpgwcVAF1Nw/MB8GA1UdIwQYMBaAFGtpKDo1L0hjQM972K9J6T7Z
# PdshMGwGA1UdHwRlMGMwYaBfoF2GW2h0dHA6Ly93d3cubWljcm9zb2Z0LmNvbS9w
# a2lvcHMvY3JsL01pY3Jvc29mdCUyMFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGlu
# ZyUyMENBJTIwMjAyMC5jcmwweQYIKwYBBQUHAQEEbTBrMGkGCCsGAQUFBzAChl1o
# dHRwOi8vd3d3Lm1pY3Jvc29mdC5jb20vcGtpb3BzL2NlcnRzL01pY3Jvc29mdCUy
# MFB1YmxpYyUyMFJTQSUyMFRpbWVzdGFtcGluZyUyMENBJTIwMjAyMC5jcnQwDAYD
# VR0TAQH/BAIwADAWBgNVHSUBAf8EDDAKBggrBgEFBQcDCDAOBgNVHQ8BAf8EBAMC
# B4AwZgYDVR0gBF8wXTBRBgwrBgEEAYI3TIN9AQEwQTA/BggrBgEFBQcCARYzaHR0
# cDovL3d3dy5taWNyb3NvZnQuY29tL3BraW9wcy9Eb2NzL1JlcG9zaXRvcnkuaHRt
# MAgGBmeBDAEEAjANBgkqhkiG9w0BAQwFAAOCAgEAAFYcd7rrNVHRZWofhE4ft9YN
# ZPVEzaQ90iE/5kCDoQlCKTE7jFYnFcfxETrL4ed8JSj0JxCZSJQVUwEp6haUSPki
# Sg4mf7rq+m3qbCjHB8Dj82rsFSxAs8NqI/08Dq1Ci/rxVhryPOSZmtXRgNeJzxwD
# qSch50pNBGQMU8APLSnwpqzhwRN76MK5PXYCVqm/u/v579+fFJh0bIsw49/wTcTC
# Xh3s0C9y0iAmSvsJKnTfEvtfe+eS9qw2wyf2LdJ5n8klFJ6OtDg8YB9n+E+0vX1E
# JIDPxN2yX7+2sJiABcUSc55jIHxPTArDdzR0YUwQIjZO0j9hIjyMbRYjgjJ4UK9Z
# LrvN2nUyc0upLqKKvhAqKP1jX0FL5M0wuneZ9/SGy2ZFn/Bg8ISBOp34ri+412tO
# lzqR9ZU+CU9Xn1MqcWXvvDhTqjexxKZMVRMqGjRECQWSA62WdCGYjEOWnH5lQJqL
# YRhYpeAwvjszdEAjSFtFXFLGTRw4bSKoad5TjUEvsKFO8DVPCjrbMEzGdku4znme
# FddbqXR41HlunpyOLuSoC1II/Bh+aX0nU19JU79T10OFRKZDFKUI3LWB9jTdT+3E
# OJr/pQ5T0fFeei0A7UdmTgXbmP4IaCbTc41NG7KMmsmV6Xyank4qB5aSL30uegrr
# vnHPjQBLLYjerGCNtQMxggdDMIIHPwIBATB4MGExCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQ
# dWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAATBtLnGPC5NN6AAAA
# AABMMA0GCWCGSAFlAwQCAQUAoIIEnDARBgsqhkiG9w0BCRACDzECBQAwGgYJKoZI
# hvcNAQkDMQ0GCyqGSIb3DQEJEAEEMBwGCSqGSIb3DQEJBTEPFw0yNTAzMjYxNDIy
# MzZaMC8GCSqGSIb3DQEJBDEiBCCAdF7LKZ+70iH16KoKq+G7gHe6B1opbKyp5rVQ
# qZVP0zCBuQYLKoZIhvcNAQkQAi8xgakwgaYwgaMwgaAEIN46bOoVmqp2Rt/G6TI8
# VIZkg7qJ8OddiPDqk6jY+midMHwwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYDVQQK
# ExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQdWJs
# aWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwAhMzAAAATBtLnGPC5NN6AAAAAABM
# MIIDXgYLKoZIhvcNAQkQAhIxggNNMIIDSaGCA0UwggNBMIICKQIBATCCAQmhgeGk
# gd4wgdsxCzAJBgNVBAYTAlVTMRMwEQYDVQQIEwpXYXNoaW5ndG9uMRAwDgYDVQQH
# EwdSZWRtb25kMR4wHAYDVQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xJTAjBgNV
# BAsTHE1pY3Jvc29mdCBBbWVyaWNhIE9wZXJhdGlvbnMxJzAlBgNVBAsTHm5TaGll
# bGQgVFNTIEVTTjo3ODAwLTA1RTAtRDk0NzE1MDMGA1UEAxMsTWljcm9zb2Z0IFB1
# YmxpYyBSU0EgVGltZSBTdGFtcGluZyBBdXRob3JpdHmiIwoBATAHBgUrDgMCGgMV
# AJueWs/5vWNYP+JGxmOfpj88ZvzBoGcwZaRjMGExCzAJBgNVBAYTAlVTMR4wHAYD
# VQQKExVNaWNyb3NvZnQgQ29ycG9yYXRpb24xMjAwBgNVBAMTKU1pY3Jvc29mdCBQ
# dWJsaWMgUlNBIFRpbWVzdGFtcGluZyBDQSAyMDIwMA0GCSqGSIb3DQEBCwUAAgUA
# 644N9jAiGA8yMDI1MDMyNjA1MjQwNloYDzIwMjUwMzI3MDUyNDA2WjB0MDoGCisG
# AQQBhFkKBAExLDAqMAoCBQDrjg32AgEAMAcCAQACAgdPMAcCAQACAhLRMAoCBQDr
# j192AgEAMDYGCisGAQQBhFkKBAIxKDAmMAwGCisGAQQBhFkKAwKgCjAIAgEAAgMH
# oSChCjAIAgEAAgMBhqAwDQYJKoZIhvcNAQELBQADggEBAI1az7pNekgZyOg9VidF
# Xk2e6nIfa/HTV40P8vkljKflj4L6jHpumsiUipJaiiSJ9BLro5O30u+DprW4Xh6p
# rNaEg3lIxIbMFKM+xND2U3me8BtPkA1Kkq02XFSGmo/Qa4u5VuH7yJIBF5a2G7J9
# ARwBijGCJ9sDKiin7F6vAM8q1XviQgf7a78wHzeWc20bcuVxdT11z0z2VAKxJ2y7
# eubbT0yzmYZk1ZBW0NwLTW3gGARVJA9HC4+MwyCs07had+3FGJEr/OdbOc66jtmg
# e1FU7H2vhbdkxPX6cpFcP9ThM7Y5/2RMf6qqU7w4N3fZcO2facvwgEANVbYMDx5x
# YgMwDQYJKoZIhvcNAQEBBQAEggIAftBgHzNEhyg6ZMaqrJs76O8voQJhiFgA3Inx
# kgnft4SG1df4ICZEiyfBRCra7z/JNRUE0yMjGANGOIMLBlJQS1/djf3fkqonHb8a
# X6J5XJH9HirNE3ynQ1r5KzKLL2/UpvLnDyKmAus+FXKwouHeG7510loh+tX5n/ep
# 1EQL6S911zMm9uBP9eTtXbRomEp/Y8DbWcUuFan6vDPwWC4rNQWJUHf29IeGg3vh
# QOGUZCBGJIXA4/VaQImMj4YGON+hPNXVGqWh3igcQOLMmWxaMDvCyrcNdW0abCHG
# Hi3IYthO6hFbJYHAH8l6cZTv19yHFrOu2WvsMIWknQS70+LaywqCKwNaul/zzi02
# AMtaidmRMQfA6O/CHJBBVB2r6ySYm0I5q/dcI6SSaxme/kgoNeLCfb7uTm5nU93f
# ocin69TCjiq9AocHwJxKtKCIuJZfB1Rx6/NUyUa9QpaHoWta5TZebR+J7YqSLcnQ
# VQCnb5+AXm/By6N8UXobamfg5hFSlHk9375zuHXiNwwoYj7xUYzXCzWlMLAma9ez
# R8sJ0d5jfQF6TDtXq2/1rGxIu3hi7BaNaKkp7VIoqzGFS8fBjwFRwqrB1xWhW6xD
# 3Fs6MwBMnSa6gqyzowyXxDDnkNsHNoN141cea/fKMEenvn0L5k5pL0RAps5AKV+c
# 2bsuESM=
# SIG # End signature block
