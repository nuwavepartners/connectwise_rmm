Properties {
	$ProjectRoot = Get-Location
	$InputDir = '.\src'
	$OutputDir = '.\build'
}

TaskSetup {
	Write-Output "".PadRight(70, '-')
}

Task Default -depends Test

Task Init {
	# Set-Location $ProjectRoot
	# Set-BuildEnvironment
	# "Build System Details:"
	# Get-Item ENV:BH*

	# Create Output Directory
	if (Test-Path -Path $OutputDir) { Remove-Item -Path $OutputDir -Force -Recurse }
	New-Item -Path $OutputDir -ItemType Directory | Out-Null

}

Task Test -depends Init {
	# Pester
	if (Test-Path -Path "$ProjectRoot\Tests" -PathType Container) {
		Import-Module Pester
		$PesterConf = [PesterConfiguration]@{
			Run        = @{
				Path     = "$ProjectRoot\Tests"
				PassThru = $true
			}
			TestResult = @{
				Enabled      = $true
				OutputPath   = ("{0}\Unit.Tests.xml" -f $ProjectRoot)
				OutputFormat = "NUnitXml"
			}
		}
		$TestResults = Invoke-Pester -Configuration $PesterConf
		If ($TestResults.FailedCount -gt 0) {
			Write-Error "Failed '$($TestResults.FailedCount)' tests, build failed" -ErrorAction Stop
		}
	}

	# PSScriptAnalyzer
	Invoke-ScriptAnalyzer -Path (Join-Path $InputDir *.ps1) -Recurse -OutVariable issues
	$errors = $issues.Where({ $_.Severity -eq 'Error' })
	$warnings = $issues.Where({ $_.Severity -eq 'Warning' })
	if ($errors) {
		Write-Error "There were $($errors.Count) errors and $($warnings.Count) warnings total." -ErrorAction Stop
	} else {
		Write-Output "There were $($errors.Count) errors and $($warnings.Count) warnings total."
	}
}

Task Build -depends Test {
	# Process Private Scripts
	$privateFunctions = @{}
	Get-ChildItem -Path "$ProjectRoot\src\Private" -Filter "*.ps1" -Recurse | ForEach-Object {
		$scriptContent = Get-Content -Path $_.FullName -Raw
		$tokens = $null; $errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$errors)
		$functionDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
		foreach ($func in $functionDefs) {
			$privateFunctions[$func.Name] = $_.FullName
		}
	}

	# Process Public Scripts
	$InputBase = Get-Item -Path (Join-Path $InputDir 'Public')
	Get-ChildItem -Path "$ProjectRoot\src\Public" -Filter "*.ps1" -Recurse | ForEach-Object {
		# Build Destination Path, Copy
		$destinationDir = Join-Path $ProjectRoot "build" (Resolve-Path -Path $_.FullName -Relative -RelativeBasePath $InputBase | Split-Path)
		If (!(Test-Path -Path $destinationDir -PathType Container)) {
			New-Item -ItemType Directory -Path $destinationDir | Out-Null
		}
		$newItem = Copy-Item -Path $_.FullName -Destination $destinationDir -PassThru

		# Analyze Content for Functions
		$scriptContent = Get-Content -Path $newItem.FullName -Raw
		$tokens = $null; $errors = $null
		$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$tokens, [ref]$errors)

		# List of Commands/Functions Called
		$functionCalls = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object {
			if ($_.CommandElements.Count -gt 0) {
				$_.CommandElements[0].Extent.Text
			}
		} | Sort-Object -Unique

		# List of Functions Defined
		$functionDefs = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

		$missingFunctions = $functionCalls | Where-Object {
			((Get-Command -Name $_ -ErrorAction SilentlyContinue) -eq $null ) -and
			($functionDefs.Name -notcontains $_)
		}

		$functionsContent = ""
		foreach ($functionName in $missingFunctions) {
			if ($privateFunctions.ContainsKey($functionName)) {
				$privateScriptContent = Get-Content -Path $privateFunctions[$functionName] -Raw
				$privateTokens = $null; $privateErrors = $null
				$privateAst = [System.Management.Automation.Language.Parser]::ParseInput($privateScriptContent, [ref]$privateTokens, [ref]$privateErrors)
				$matchingFunc = $privateAst.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $args[0].Name -eq $functionName }, $true) | Select-Object -First 1

				if ($matchingFunc) {
					$functionsContent += $matchingFunc.Extent.Text + "`n`n"
				}
			} else {
				throw ('Missing Function: {0}' -f $functionName)
			}
		}

		$updatedScriptContent = $scriptContent -replace '#FUNCTIONS#', $functionsContent
		Set-Content -Path $newItem.FullName -Value $updatedScriptContent
	}


}

Task Publish -depends Build {
	$publishParams = @{
		Path        = $env:BHPSModulePath
		NuGetApiKey = $env:NuGetApiKey
	}

	if ($Repository) {
		$publishParams['Repository'] = $Repository
	}

	Publish-Module @publishParams
}