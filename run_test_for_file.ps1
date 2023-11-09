Param(
	[Parameter(Mandatory=$True, HelpMessage="Starting/root directory to search the test file in")]
	[ValidateNotNullOrEmpty()]
	[string]$startDir,

	[Parameter(Mandatory=$True, HelpMessage="Absolute path, relative path (to `$startDir), or name, of a source/project (not a header) test file")]
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

	[Parameter(Mandatory=$False, HelpMessage="Test names to be run, if provided then either a file having a single class or a single `$classNames element has to be explicitly provided")]
	[AllowNull()]
	[string]$testName = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Tests to be included in the test run e.g. FULL or EXTENDED")]
	[ValidateSet("/includefull", "/includeextended")]
	[string]$includeOption = "/includefull",

	[Parameter(Mandatory=$False, HelpMessage="Whether the tests should be run in RETAIL mode")]
	[switch]$retail,

	[Parameter(Mandatory=$False, HelpMessage="Print all the info during script execution, w/o actually running any commands")]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

# Include safe file-finding functions
. "$($PSScriptRoot)/common/_find_file_common_safe.ps1"

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

[string]$fileAbsPath = FindAbsolutePathInStartDir -startDir $startDir -filePath $filePath 
If ([string]::IsNullOrWhiteSpace($fileAbsPath)) {
	ScriptFailure "No test file found"
}

[string]$projectPath = FindProjectForFileInStartDir -startDir $startDir -filePath $fileAbsPath
If ([string]::IsNullOrWhiteSpace($projectPath)) {
	ScriptFailure "No test project found"
}

[string]$assemblyName = find_first_match -filePath $projectPath -pattern "<AssemblyName>\s*([^\s]+)\s*</AssemblyName>"
# Assembly name might not be provided with an extension in the project file
If (-Not ($assemblyName.EndsWith(".dll") -Or $assemblyName.EndsWith(".exe"))) {
	$assemblyName = "$($assemblyName).dll"
}

Log Verbose "Found assembly [$($assemblyName)] in project [$($projectPath)]"

[string]$namespace = find_first_match -filePath $fileAbsPath -pattern "^\s*namespace\s+([^\s]+)"
Log Verbose "Found namespace [$($namespace)] in file [$($fileAbsPath)]"

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
	[string[]]$classOnlyNames = Select-String -Path $fileAbsPath -Pattern "^\s*((public)|(internal))(.*)class\s+(\w+)" |
		Select-Object -ExpandProperty Matches |
		Where-Object { -Not ($_.Groups[4].Value -imatch "abstract") } |
		ForEach-Object { $_.Groups[5].Value } |
		Where-Object { -Not [string]::IsNullOrWhiteSpace($_) }
	$classNames = $classOnlyNames |
		ForEach-Object { "$($namespace).$($_)" }
	If ($classNames.Length -Gt 0) {
		Log Verbose "Found $($classNames.Length) class(es) in test file [$($fileAbsPath)]" `
			-additionalEntries "@($(($classOnlyNames | ForEach-Object { "'$($_)'" }) -join ", "))"
	} Else {
		ScriptFailure "Found no classes in test file [$($fileAbsPath)]"
	}
}

LogNewLine
[System.Diagnostics.StopWatch]$totalStopWatch = [System.Diagnostics.StopWatch]::StartNew()
[string]$totalDurationStr = $Null
For ([Uint16]$ci = 0; $ci -Lt $classNames.Length; $ci++) {
	[string]$fullClassName = $classNames[$ci]
	# Remove namespace from the class, use only its short name for logging
	[string]$classNameShort = $fullClassName -replace "^.*\.",""
	[string]$classInfo = "Test class '$($classNameShort)' #$($ci + 1)/$($classNames.Length)"
	[string]$testCommand = "$($suitesPath) /assembly $($assemblyName) /className $($fullClassName) /envFile `"$($environmentXmlFilePath)`" $($includeOption)"
	If (-Not [string]::IsNullOrEmpty($testName)) {
		If (1 -Ne $classNames.Count) {
			ScriptFailure "When test name (e.g. '$($testName)') is provided - a single class has to be provided, but $($classNames.Count) classes detected"
		}

		$testCommand = "$($testCommand) /testId $($testName)"
	}

	If ($retail.IsPresent) {
		$testCommand = "$($testCommand) /retail"
	}

	Log Info "$($classInfo) command:" -additionalEntries @("$($testCommand)`n")
	If (-Not $dryRun.IsPresent) {
		If ($ci -Gt 0) {
			[UInt16]$sleepInS = 60
			Log Verbose "Sleeping for $($sleepInS)s before starting next test class in order to process previous results"
			Start-Sleep -Seconds $sleepInS
		}

		[System.Diagnostics.StopWatch]$currentTestStopWatch = [System.Diagnostics.StopWatch]::StartNew()
		# Do not use RunCommand as it will hide all the test logs
		Invoke-Expression -Command $testCommand
		[string]$currentTestDurationStr = GetStopWatchDuration -stopWatch $currentTestStopWatch -stop
		# Do not stop the global stopwatch, continue measuring time until all test classes are executed
		$totalDurationStr = GetStopWatchDuration -stopWatch $totalStopWatch
		Log Success "$($classInfo) executed in $($currentTestDurationStr) (total duration $($totalDurationStr))"
	}
}

$totalDurationStr = GetStopWatchDuration -stopWatch $totalStopWatch -stop
If (-Not $dryRun.IsPresent) {
	LogNewLine
	Log Success "Executed $($classNames.Length) class(es) in test file [$($fileAbsPath)] in $($totalDurationStr)"
}
