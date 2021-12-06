Param(
	[Parameter(Mandatory=$True, HelpMessage="Starting/root directory to search the test file in")]
	[ValidateNotNullOrEmpty()]
	[string]$startDir,

	[Parameter(Mandatory=$True, HelpMessage="File absolute path, file relative path (to `$startDir), or file name")]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$True, HelpMessage="Absolute path of suites.cmd used for running TestShell tests")]
	[ValidateNotNullOrEmpty()]
	[string]$suitesPath,

	[Parameter(Mandatory=$True, HelpMessage="Absolute path of TestShell environment XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$environmentXmlFilePath,

	[Parameter(Mandatory=$False, HelpMessage="Test class names to be run, if blank/empty all the test classes in the file will be used")]
	[string[]]$classNames = @(),

	[Parameter(Mandatory=$False, HelpMessage="Tests to be included in the test run e.g. FULL or EXTENDED")]
	[ValidateSet("/includefull", "/includeextended")]
	[string]$includeOption = "/includefull",

	[Parameter(Mandatory=$False, HelpMessage="Print all the info during script execution, w/o actually running any commands")]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"
# Include find-project function
. "$($PSScriptRoot)/work/find_project_for_file.ps1"

function find_first_match() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$filePath,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$pattern)
	[string[]]$matches = Select-String -Path $filePath -Pattern $pattern |
		Select-Object -ExpandProperty Matches |
		ForEach-Object { $_.Groups[1].Value } |
		Where-Object { -Not [string]::IsNullOrWhiteSpace($_) }
	If ($matches.Length -Eq 0) {
		ScriptFailure "Did not find any matches '$($pattern)' in [$($filePath)]"
	} ElseIf ($matches.Length -Gt 1) {
		ScriptFailure "Found $($namespaces.Length) matches '$($pattern)'' in [$($filePath)]"
	}

	return $matches[0]
}

$filePath = find_absolute_path_in_start_dir -startDir $startDir -filePath $filePath

[string]$projectPath = find_project_for_file_in_start_dir -startDir $startDir -filePath $filePath
[string]$assemblyName = find_first_match -filePath $projectPath -pattern "<AssemblyName>\s*([^\s]+)\s*</AssemblyName>"
# Assembly name might not be provided with an extension in the project file
If (-Not ($assemblyName.EndsWith(".dll") -Or $assemblyName.EndsWith(".exe"))) {
	$assemblyName = "$($assemblyName).dll"
}

LogInfo "Found assembly [$($assemblyName)] in project [$($projectPath)]"

[string]$namespace = find_first_match -filePath $filePath -pattern "^\s*namespace\s+([^\s]+)"
LogInfo "Found namespace [$($assemblyName)] in file [$($filePath)]"

If ($classNames.Length -Gt 0) {
	$classNames = $classNames |
		ForEach-Object {
			If ($_.StartsWith($namespace)) {
				return $_
			} ElseIf ($_.Contains(".")) {
				ScriptFailure "Class [$($_)] contains invalid namespace, expected [$($namespace)]"
			} Else {
				return "$($namespace).$($_)"
			}
		}
} Else {
	$classNames = Select-String -Path $filePath -Pattern "^\s*public(.*)class\s+([^\s]+)" |
		Select-Object -ExpandProperty Matches |
		Where-Object { -Not ($_.Groups[1].Value -imatch "abstract") } |
		ForEach-Object { $_.Groups[2].Value } |
		Where-Object { -Not [string]::IsNullOrWhiteSpace($_) } |
		ForEach-Object { "$($namespace).$($_)" }
	If ($classNames.Length -Gt 0) {
		LogInfo "Found $($classNames.Length) class(es) in test file [$($filePath)]"
	} Else {
		ScriptFailure "Found no classes in test file [$($filePath)]"
	}
}

LogNewLine
[System.Diagnostics.StopWatch]$stopWatch = [System.Diagnostics.StopWatch]::StartNew()
For ([Uint16]$ci = 0; $ci -Lt $classNames.Length; $ci++) {
	[string]$className = $classNames[$ci]
	[string]$classNumberInfo = "$($ci + 1)/$($classNames.Length)"
	[string]$testCommand = "$($suitesPath) /assembly $($assemblyName) /className $($className) /envFile `"$($environmentXmlFilePath)`" $($includeOption)"
	LogInfo "Test class #$($classNumberInfo) command:`n`t$($testCommand)`n"
	If (-Not $dryRun.IsPresent) {
		If ($ci -Gt 0) {
			[UInt16]$sleepInS = 60
			LogInfo "Sleeping for $($sleepInS)s before starting next test class in order to process previous results"
			Start-Sleep -Seconds $sleepInS
		}

		# Do not use RunCommand as it will hide all the test logs
		Invoke-Expression -Command $testCommand
		# Do not stop the stopwatch, continue measuring time until all test classes are executed
		LogInfo "Executed $($classNumberInfo) test class(es) in $(GetStopWatchDuration -stopWatch $stopWatch)"
	}
}

[string]$durationStr = GetStopWatchDuration -stopWatch $stopWatch -stop
If (-Not $dryRun.IsPresent) {
	LogNewLine
	LogSuccess "Executed $($classNames.Length) classes in test file [$($filePath)] in $($durationStr)"
}