[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Error code e.g. 'SYS_ATTN'")]
	[ValidateNotNullOrEmpty()]
	[string]$errorCode,

	[Parameter(Mandatory=$False, HelpMessage="Target state value to display information for")]
	[AllowNull()]
	[AllowEmptyString()]
	[string]$targetState,

	[Parameter(Mandatory=$False, HelpMessage="Should we list all files where an error state is thrown")]
	[switch]$includeFileInfo,

	[Parameter(Mandatory=$False, HelpMessage="DsMainDev repo path, defaulting to ROOT environment variable (set from CoreXT).")]
	[ValidateNotNullOrEmpty()]
	[string]$dsMainRepoPath = $env:ROOT,

	[Parameter(Mandatory=$False, HelpMessage="Search subfolder.")]
	[ValidateNotNullOrEmpty()]
	[string]$searchSubfolder = "Sql",

	[Parameter(Mandatory=$False, HelpMessage="Show debug logs (internal to this script)")]
	[switch]$showDebugLogs)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[string]$searchPath = Join-Path -Path $dsMainRepoPath -ChildPath $searchSubfolder

Log Verbose "Searching for all occurrences of raising [$($errorCode)] error in CPP files in [$($searchPath)]..."
LogNewLine

function processErrorState() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[HashTable]$stateCount,
		[Parameter(Mandatory=$True)]
		[object]$state,
		[Parameter(Mandatory=$True)]
		[string]$filePath)
	# Use a cache field 'count' for easy access to total count in all files
	If (-Not $stateCount.ContainsKey($state)) {
		$stateCount[$state] = @{ fileMap = @{}; count = 0; }
	}

	$stateCount[$state].fileMap[$filePath]++
	$stateCount[$state].count++
}

function printStates() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[HashTable]$stateCount,
		[Parameter(Mandatory=$False)]
		[string]$statePrefix = "",
		[Parameter(Mandatory=$False)]
		[string]$stateSuffix = "")
	If ($stateCount.Count -Eq 0) {
		return
	}

	$stateCount.Keys |
		Sort-Object |
		ForEach-Object {
			[string]$logType = "Verbose"
			[object]$state = $_
			[HashTable]$currentFileMap = $stateCount[$state].fileMap
			[Int32]$currentCount = $stateCount[$state].count
			If ($currentCount -Gt 10) {
				$logType = "Error"
			} ElseIf ($currentCount -Gt 1) {
				$logType = "Warning"
			}

			[string]$message = "State $($statePrefix)$($_)$($stateSuffix)"
			If ($currentCount -Gt 1) {
				# Append number of occurrences for each state used multiple times
				$message = "$($message) is found $($currentCount) time(s) in total"
				If (-Not $includeFileInfo.IsPresent) {
					# If we are not listing files - at least show their count
					$message = "$($message) in $($currentFileMap.Count) file(s)"
				}
			}

			[string[]]$additionalEntries = @()
			If ($includeFileInfo.IsPresent) {
				# Sort by count of matches in the file, then by file path
				$additionalEntries = $currentFileMap.Keys |
					Sort-Object -Descending { $currentFileMap[$_] },{$_} |
					ForEach-Object {
						[string]$fileMessage = "[$($_)]"
						If ($currentCount -Gt 1) {
							$fileMessage = "$($currentFileMap[$_]) time(s) in $($fileMessage)"
						}
						return $fileMessage
					}
			}

			Log $logType $message -indentLevel 1 -additionalEntries $additionalEntries -entryPrefix "- "
		}
	LogNewLine
}

function getTotal() {
	[OutputType([Int32])]
	Param(
		[Parameter(Mandatory=$True)]
		[HashTable]$stateCount)
	return ($stateCount.Values | ForEach-Object { $_.count } | Measure-Object -Sum).Sum
}

# Keep track of total error code matches, even when we are not throwing an error
[Int32]$totalErrorCodeMatches = 0

# Hash tables of number/variable-state to (file) counts
[HashTable]$stateNumberCount = @{}
[HashTable]$stateVarCount = @{}

# Check whether we are using ex_raise*|ex_callprint*|SqlError() family of functions/constructors
[string]$exceptionInfo = "(alg_)ex_raise*|ex_callprint*|SqlError"
[string]$exceptionRegex = "\b(((alg_)?ex_raise(\d*))|(ex_callprint\w*)|(SqlError))\b"
# Error code is followed by severity then state parameters e.g.
# - ex_raise*(CODE, SEVERITY, STATE);
# - alg_ex_raise(LINE, CODE, SEVERITY, STATE);
# - ex_callprint*(EX_NUMBER(MAJOR, CODE), SEVERITY, STATE, PARAM1, ...);
# - SqlError(EX_NUMBER(MAJOR, CODE), SEVERITY, STATE, PARAM1, ...);
# - SqlError(MAJOR, CODE, SEVERITY, STATE);
# State will be followed by
# - comma and parameters e.g. ", value1, value2);"
# - closing bracket and command-terminating semicolon i.e. ");"
# - comment block e.g. "/*" or "//"
[string]$stateRegex = "\b$($errorCode)\b\s*\)*,[^,]*,([^,\)/]+)(,|\)|(//)|(/\*))"

# Observe only CPP files
Get-ChildItem -Path $searchPath -Filter "*.cpp" -Recurse |
	Select-String -Pattern "\b$($errorCode)\b" -Context 2,5 |
	ForEach-Object {
		# Increase the total number of error code matches
		$totalErrorCodeMatches++

		if (-Not ($_.Context.PreContext -imatch $exceptionRegex -Or $_.Line -imatch $exceptionRegex)) {
			If ($showDebugLogs.IsPresent) { Log Warning "Not using $($exceptionInfo) for a match in [$($_.Path)]" -additionalEntries @($_); LogNewLine }
			return
		}

		# Trim the matched lines and extract state.
		[string]$state = "$($_.Line)$($_.Context.PostContext)" -replace "[\r\n]+","" |
			Select-String -Pattern $stateRegex |
			ForEach-Object { $_.Matches[0].Groups[1] }
		If ([string]::IsNullOrWhiteSpace($state)) {
			If ($showDebugLogs.IsPresent) { Log Warning "State not found for a match in [$($_.Path)]:" -additionalEntries @($_); LogNewLine }
			return
		}

		$state = $state.Trim()
		If ((-Not [string]::IsNullOrEmpty($targetState)) -And ($state -INe $targetState)) {
			If ($showDebugLogs.IsPresent) { Log Verbose "Ignoring state $($state)" -additionalEntries @("@ [$($_.Path) : $($_.LineNumber)]") }
			return
		}

		If ($state -imatch "^\d+$") {
			If ($showDebugLogs.IsPresent) { Log Verbose "Found numeric state #$($state)" -additionalEntries @("@ [$($_.Path) : $($_.LineNumber)]") }
			processErrorState -stateCount $stateNumberCount -state ([Int32]$state) -filePath $_.Path
		} Else {
			If ($showDebugLogs.IsPresent) { Log Verbose "Found variable state '$($state)'" -additionalEntries @("@ [$($_.Path) : $($_.LineNumber)]") }
			processErrorState -stateCount $stateVarCount -state $state -filePath $_.Path
		}
	}

Log Verbose "The error code [$($errorCode)] is found $($totalErrorCodeMatches) time(s) in CPP files throughout the SQL codebase."

[Int32]$totalStatesFound = $stateNumberCount.Count + $stateVarCount.Count
[string]$foundStateDescription = "$($totalStatesFound) different state(s)"
[string]$notFoundStateDescription = "existing states"
If (-Not [string]::IsNullOrEmpty($targetState)) {
	$foundStateDescription = "target state $($targetState)"
	$notFoundStateDescription = "target state $($targetState)"
}

If ($totalStatesFound -Eq 0) {
	Log Error "No $($notFoundStateDescription) found. The error doesn't seem to have been explicitly thrown via $($exceptionInfo) family of functions."
	return
}

Log Info "Found $($foundStateDescription) with $((getTotal -stateCount $stateNumberCount) + (getTotal -stateCount $stateVarCount)) total occurrence(s) for error [$($errorCode)]"

printStates -stateCount $stateVarCount -statePrefix "variable '" -stateSuffix "'"
printStates -stateCount $stateNumberCount -statePrefix "#"

If (-Not [string]::IsNullOrEmpty($targetState)) {
	# If we were interested only in a specific target state
	# then do no more processing (e.g. for next available numeric state).
	return
}

[Int32]$minAvailableState = 1
While ($minAvailableState -Lt [Int32]::MaxValue) {
	If (-Not $stateNumberCount.ContainsKey($minAvailableState)) {
		break;
	}

	$minAvailableState++
}

[Int32]$maxAvailableState = ($stateNumberCount.Keys | Measure-Object -Maximum).Maximum + 1
Log Info "Available integer states: minimum $($minAvailableState), next maximum $($maxAvailableState)"

If ($stateVarCount.Count -Gt 0) {
	Log Warning "Note that there are $($stateVarCount.Count) variable states, check manually and avoid their integer values. See above logs for more details."
}
