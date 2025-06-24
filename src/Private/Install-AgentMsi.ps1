function Install-AgentMsi {
	param(
		[string] $MSIPath,
		[string] $Token
	)
	Write-Verbose "Installing $MSIPath"
	$installer = New-WindowsInstallerInstaller
	Set-WindowsInstallerInstallerUILevel -UILevel 2 -Installer $installer
	$session = Open-WindowsInstallerPackage -PackagePath $MSIPath
	Set-WindowsInstallerSessionProperty -Session $session -PropertyName 'TOKEN' -PropertyValue $Token
	Invoke-WindowsInstallerSessionAction -Session $session -Action 'INSTALL'
}