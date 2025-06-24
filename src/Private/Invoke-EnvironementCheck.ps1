function Invoke-EnvironmentCheck {
	Write-Verbose "Checking TLS Protocols"
	[Net.ServicePointManager]::SecurityProtocol = [System.Enum]::GetValues([System.Net.SecurityProtocolType]) | Where-Object { $_ -match 'Tls' };

	Write-Verbose "Checking Execution Policy"
	if (@('Unrestricted', 'RemoteSigned', 'Bypass') -notcontains (Get-ExecutionPolicy -Scope Process)) {
		Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force -ErrorAction SilentlyContinue
	}

	Write-Verbose "Checking NuGet and PowerShell Gallery"
	Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force | Out-Null
	Set-PSRepository -Name PSGallery -InstallationPolicy Trusted

	Write-Verbose "Checking PowerShell Modules"
	$requiredModules = @{
		"PS-WindowsInstaller" = [version]"1.2"
		"PsIni"               = [version]"3.1.2"
	}
	foreach ($moduleName in $requiredModules.Keys) {
		$requiredVersion = $requiredModules[$moduleName]
		Write-Verbose "Checking $moduleName module..."
		$module = Get-Module $moduleName -ListAvailable
		if (-not $module) {
			Write-Verbose "$moduleName module not found. Installing..."
			if ((New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
				Install-Module $moduleName -Force -Scope AllUsers
			} else {
				Install-Module $moduleName -Force -Scope CurrentUser
			}
		} elseif ($module.Version -lt $requiredVersion) {
			Write-Verbose "$moduleName module version $($module.Version) is less than $($requiredVersion). Updating..."
			Update-Module $moduleName -Force
		} else {
			Write-Verbose "$moduleName module version $($module.Version) is $($requiredVersion) or higher."
		}
		Import-Module $moduleName -Force
		Write-Verbose "$moduleName module loaded."
	}
}