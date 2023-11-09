Param(
	[Parameter(Mandatory=$False, HelpMessage="Validation gate (ES team enforces test pass rate on `"Auto-Functionals`" gate)")]
	[ValidateSet(
		, "Auto-Functionals"
		, "Auto-Functionals/CI"
		, "Auto-Functionals/Functional"
		, "Auto-Functionals/Functional/Engine"
		, "Auto-Functionals/Functional/XDB"
		, "Auto-Functionals/Functional/DW"
		, "Cluster Validation"
		, "CT Trident"
		, "DW Gen3"
	)]
	[string]$validationGate = "Auto-Functionals",

	[Parameter(Mandatory=$False, HelpMessage="Validation key override, explicitly set (>= 0) will override `$validationGate")]
	[Int16]$validationKeyOverride = -1,

	[Parameter(Mandatory=$False, HelpMessage="Validation dimension override, explicitly set (>= 0) will override `$validationGate")]
	[Int16]$validationDimensionOverride = 0,

	[Parameter(Mandatory=$False, HelpMessage="Relevant aliases whose builds should be highlighted")]
	[string[]]$relevantAliases = @("AVAdmin", $env:USERNAME),

	[Parameter(Mandatory=$False, HelpMessage="Number of past hours (to look back) in the validation report. ES team enforces 5 day (120h) maximum for PR policy.")]
	[ValidateScript({ $_ -Ge 12 })]
	[UInt16]$lookbackHours = 108,

	[Parameter(Mandatory=$False, HelpMessage="Test pass rate threshold - ignored if set to 0. ES team enforces a minimum for PR policy, which is subject to change, but on 2023-08-28 it was 99.6%.")]
	[ValidateScript({ $_ -Ge 0 -And $_ -Le 100 })]
	[Double]$testPassRateThreshold = 0,

	# We want to have results with test pass rates included, so do not allow 0 here.
	[Parameter(Mandatory=$False, HelpMessage="Test pass rate format - 0 (None) e.g. 'Failed', 1 (Actual) e.g. 'Failed (99.5%)', 2 (Projected) e.g. 'Failed 99.62'")]
	[ValidateSet(1, 2)]
	[UInt16]$testPassRateFormat = 1,

	[Parameter(Mandatory=$False, HelpMessage="Project to search LKGC (last-known-good-changeset) for")]
	[ValidateNotNullOrEmpty()]
	[string]$projectBranch = "DS_MAIN_DEV_GIT",

	[Parameter(Mandatory=$False, HelpMessage="Target build ID to be used (if successful) - value in the (usually leftmost) column named [ID] in the validation report)")]
	[string]$targetBuildId = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Perform the sync to the LGKC (i.e. the commit ID discovered, if available)")]
	[switch]$sync,

	[Parameter(Mandatory=$False, HelpMessage="Ignore recent cached contents (by default reused for an hour) of the validation report")]
	[switch]$ignoreCache,

	[Parameter(Mandatory=$False, HelpMessage="Print all rows/entries containing build information in the validation report")]
	[switch]$printAllBuildInfo,

	[Parameter(Mandatory=$False, HelpMessage="Show debug logs (internal to this script)")]
	[switch]$showDebugLogs,

	[Parameter(Mandatory=$False, HelpMessage="Skip (i.e. not log) additional git details for commits")]
	[switch]$skipGitDetails)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"
. "$($PSScriptRoot)/../git/_git_common_safe.ps1"

$ErrorActionPreference = "Stop"

[Int]$MandatoryColumnsLeft = 8
[Int]$MandatoryColumnsRight = 2
[Int]$MandatoryColumnsTotal = $MandatoryColumnsLeft + $MandatoryColumnsRight
[string]$StatusDelimiter = " / "

[bool]$global:isBranchInfoUpdated = $False

[string]$TestPassRateRegex = "[\s\(\)\d\.%]*";

function getBuildStatusTable() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$projectBranch,

		[Parameter(Mandatory=$True)]
		[UInt16]$lookbackHours)

	[Int16]$validationKey = $validationKeyOverride
	[Int16]$validationDimension = $validationDimensionOverride
	If ($validationKey -Ge 0 -And $validationDimension -Ge 0) {
		Log Info "Using explicitly set validation key $($validationKey) / dimension $($validationDimension)"
	} Else {
		switch ($validationGate) {
			"Cluster Validation" {
				$validationKey = 16
				$validationDimension = 0
			}
			"CT Trident" {
				$validationKey = 339
				$validationDimension = 0
			}
			"DW Gen3" {
				$validationKey = 266
				$validationDimension = 0
			}
			"Auto-Functionals" {
				$validationKey = 35
				$validationDimension = 0
			}
			"Auto-Functionals/CI" {
				$validationKey = 14
				$validationDimension = 0
			}
			"Auto-Functionals/Functional" {
				$validationKey = 15
				$validationDimension = 0
			}
			"Auto-Functionals/Functional/Engine" {
				$validationKey = 38
				$validationDimension = 0
			}
			"Auto-Functionals/Functional/XDB" {
				$validationKey = 39
				$validationDimension = 0
			}
			"Auto-Functionals/Functional/DW" {
				$validationKey = 6
				$validationDimension = 0
			}
		}

		Log Info "Validation gate [$($validationGate)] -> key $($validationKey) / dimension $($validationDimension)"
	}

	$cacheValidityInMinutes = 60;
	$cacheFilePath = Join-Path -Path $PSScriptRoot -ChildPath "../cache/build_status_table_cache_$($projectBranch)_V$($validationKey)-$($validationDimension)_T$($testPassRateFormat)_L$($lookbackHours)h.txt"
	If (Test-Path -Path $cacheFilePath) {
		$creationTime = (Get-Item -Path $cacheFilePath).CreationTime
		$cacheFileContent = Get-Content -Path $cacheFilePath
		If ($creationTime -Gt (Get-Date).AddMinutes(-$cacheValidityInMinutes) -And
			(-Not [string]::IsNullOrWhitespace($cacheFileContent))) {
			If (-Not $ignoreCache.IsPresent) {
				Log Info "[$($projectBranch)] Using contents from [$($cacheFilePath)] created @ [$($creationTime)]"
				return $cacheFileContent
			} Else {
				Log Warning "[$($projectBranch)] Ignoring valid cache @ [$($cacheFilePath)]"
			}
		} Else {
			Log Warning "[$($projectBranch)] Removing stale/empty cache @ [$($cacheFilePath)]"
			Remove-Item -Path $cacheFilePath
		}
	}

	[string]$baseUri = "https://troubleshooter.redmond.corp.microsoft.com/CVReport.aspx"
	[string]$targetUri = "$($baseUri)?LastHours=$($lookbackHours)&PassRate=$($testPassRateFormat)&Branch=$($projectBranch)&Title=$($projectBranch)&Key=$($validationKey)&Dim=$($validationDimension)"

	Log Verbose "[$($projectBranch)] Downloading DS CI status from [$($targetUri)]"
	$html = (Invoke-WebRequest -Uri $targetUri).Content
	If ($Null -Eq $html) {
		ScriptFailure "Failed to get HTML from [$($targetUri)]"
	}

	Log Verbose "[$($projectBranch)] Removing all new lines and link (<a>) tags to avoid XML parsing errors"
	$htmlMin = $html -replace "(\r?\n)|(</?a[^>]*>)", ""

	$tableMatch = Select-String -InputObject $htmlMin -Pattern "<table[^>]*>.*</table>"
	If ($Null -Eq $tableMatch) {
		ScriptFailure "Table element was not found in HTML @ [$($targetUri)].`nTry increasing `$lookbackHours value (currently $($lookbackHours) hours)"
	}

	$buildStatusTable = $tableMatch.Matches[0].Groups[0].Value
	Log Info "[$($projectBranch)] Caching values @ [$($cacheFilePath)] reusable for $($cacheValidityInMinutes) minutes"
	CreateFileIfNotExists -filePath $cacheFilePath
	$buildStatusTable | Out-File -FilePath $cacheFilePath

	# If we are not using cache, but getting new data then update branch info first.
	If (-Not $skipGitDetails.IsPresent) {
		LogNewLine
		Log Verbose "Updating branch info in order to get correct commit details"
		UpdateBranchesInfoFromRemoteSafely | Out-Null
		LogNewLine

		$global:isBranchInfoUpdated = $True
	}

	return $buildStatusTable
}

function getGitCommitHash() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$projectBranch)

	switch ($projectBranch) {
		"DS_MAIN_DEV_GIT" { return $row.td[2] }
		default { return $Null }
	}
}

function getRowDebugInfo() {
	[OutputType([string])]
	Param(
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row)
	[string[]]$tdValues = $row.td |
		ForEach-Object { If ($_ -is [string]) { $_ } Else { $_.InnerText } }
	return "[$($tdValues -join ', ')]"
}

function getRowStatus() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns)
	[object[]]$tds = $row.td
	If ($tds.Length -Gt $MandatoryColumnsTotal) {
		[string[]]$statuses = $validationColumns |
			ForEach-Object { $tds[$_].InnerText } |
			Where-Object { -Not [string]::IsNullOrEmpty($_) }
		# Are all columns valid?
		If ($statuses.Count -Eq $validationColumns.Count) {
			return $statuses -join $StatusDelimiter
		}

		If ($showDebugLogs) {
			Log Warning "Found only $($statuses.Count) valid status columns, $($validationColumns.Count) expected"
		}
	} ElseIf ($showDebugLogs) {
		Log Warning "Found only $($tds.Length) columns, more than $($MandatoryColumnsTotal) mandatory columns expected"
	}

	return $Null
}

function isRowValid() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns)

	[bool]$isRowValid = ($Null -Ne $row.td -And
		$row.td.Count -Gt $MandatoryColumnsTotal -And
		(-Not [string]::IsNullOrWhiteSpace((getRowStatus -row $row -validationColumns $validationColumns))))
	If ($showDebugLogs.IsPresent) {
		[string]$rowDebugInfo = getRowDebugInfo -row $row
		If ($isRowValid) {
			Log Success "Row valid: $($rowDebugInfo)" -noPersist
		} Else {
			Log Error "Row invalid: $($rowDebugInfo)" -noPersist
		}
	}

	return $isRowValid
}

function isRowBuildTestPassRateSuccessful() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns)
	If ($testPassRateThreshold -Le 0) {
		# Minimum test pass rate threshold not defined - mark as success
		return $True
	}

	[string[]]$buildStatuses = $validationColumns | ForEach-Object { $row.td[[Int]$_].InnerText }
	If ($buildStatuses.Count -Eq 0) {
		# No build statuses found - mark as failed (i.e. under pass rate threshold)
		return $False
	}

	For ([Int]$i = 0; $i -Lt $buildStatuses.Count; $i++) {
		[string]$buildStatusInfo = "Build status #$($i) '$($buildStatuses[$i])'"
		[string]$passRateMatch = [System.Text.RegularExpressions.Regex]::Match($buildStatuses[$i],'(\d+\.?\d*)').Groups[1].Value
		If ([string]::IsNullOrWhiteSpace($passRateMatch)) {
			# No pass rate found for build status - mark as failed (i.e. under pass rate threshold)
			If ($showDebugLogs.IsPresent) { Log Verbose "$($buildStatusInfo) does not have a test pass rate" }
			return $False
		}

		[Double]$passRateValue = 0
		If (-Not [Double]::TryParse($passRateMatch, [ref]$passRateValue)) {
			If ($showDebugLogs.IsPresent) { Log Warning "$($buildStatusInfo) has an invalid test pass rate '$($passRateMatch)'" }
			return $False
		}

		If ($passRateValue -Lt $testPassRateThreshold) {
			If ($showDebugLogs.IsPresent) { Log Verbose "$($buildStatusInfo) has a test pass rate $($passRateValue) under threshold $($testPassRateThreshold)" }
			return $False
		}
	}

	If ($showDebugLogs.IsPresent) { Log Success "Build status $(getRowStatus -row $row -validationColumns $validationColumns) has a test pass rate over threshold $($testPassRateThreshold)" }
	return $True
}

function getLogTypeForRowBuild() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns)
	[string]$rowStatus = getRowStatus -row $row -validationColumns $validationColumns
	[string]$logType = "Warning"
	[bool]$isSuccessfulBuild = $rowStatus -imatch "^(Passed$($TestPassRateRegex)($($StatusDelimiter))?)+$"
	If ($isSuccessfulBuild) {
		$logType = "Success"
	} ElseIf ($rowStatus.Contains("Failed")) {
		$logType = "Error"
	}

	If ($showDebugLogs.IsPresent) {
		[string[]]$additionalEntries = @((getRowDebugInfo -row $row), "status: $($rowStatus)")
		If ($isSuccessfulBuild) {
			Log Success "Row build successful:" -additionalEntries $additionalEntries -noPersist
		} Else {
			Log $logType "Row build is not successful:" -additionalEntries $additionalEntries -noPersist
		}
	}

	return $logType
}

function printRow() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$prefix,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$projectBranch,

		[Parameter(Mandatory=$False)]
		[AllowNull()]
		[string]$currentCommit,

		[Parameter(Mandatory=$False)]
		[switch]$alwaysLog)

	[object[]]$tds = $row.td;
	[string]$id = $tds[0]
	[string]$commitHash = getGitCommitHash -row $row -projectBranch $projectBranch
	[string]$descendantId = $tds[3]
	[string]$descendantType = $tds[4]
	[string]$time = $tds[5]
	[string]$alias = $tds[6]
	[string]$status = getRowStatus -row $row -validationColumns $validationColumns
	[string]$latency = $tds[$tds.Count - 2]

	[string]$logType = getLogTypeForRowBuild -row $row -validationColumns $validationColumns

	[string]$testPassRateStatus = $Null
	If ($testPassRateThreshold -Gt 0) {
		[string]$testPassRateStatus = "under"
		If (isRowBuildTestPassRateSuccessful -row $row -validationColumns $validationColumns) {
			$testPassRateStatus = "over"
		}
		[string]$testPassRateType = switch ($testPassRateFormat) {
			0 { "none"; break }
			1 { "actual"; break }
			2 { "projected"; break }
			default { "unknown"; break }
		}
		$status = "$($status) - $($testPassRateStatus) '$($testPassRateType)' test pass rate threshold ($($testPassRateThreshold)%)"
	}

	# The current commit might be full version, and the build-row commit short, so only check it as a prefix.
	[bool]$isCurrent = (-Not [string]::IsNullOrEmpty($currentCommit)) -And $currentCommit.StartsWith($commitHash)

	If (-Not ($alwaysLog.IsPresent -Or $showDebugLogs.IsPresent -Or $logType -IEq "Success" -Or $testPassRateStatus -IEq "over" -Or $isCurrent)) {
		# This commit is not really relevant - do not explicitly log it
		return
	}

	[string]$logDelimiter = "# # # # # # # # # # # # # # # # # # # # #"
	[bool]$useLogDelimiter = $isCurrent -Or ($relevantAliases -icontains $alias)
	If ($useLogDelimiter) {
		LogNewLine
		Log Info $logDelimiter
	}

	[string]$message = "$($prefix): ID #$($id) by [$($alias)] @ [$($time)], E2E latency: $($latency)"
	[string]$descendantInfo = "-"
	If (-Not [string]::IsNullOrWhiteSpace($descendantId)) {
		$descendantInfo = "#$($descendantId)"
	}

	If (-Not [string]::IsNullOrWhiteSpace($descendantType)) {
		$descendantInfo	= "$($descendantInfo) (type $($descendantType))"
	}

	[string[]]$additionalEntries = @("Status: $($status)", "Descendant: $($descendantInfo)", "Commit hash [$($commitHash)]")
	If (-Not $skipGitDetails.IsPresent) {
		# See https://git-scm.com/docs/git-show#_pretty_formats for format descriptions
		[string[]]$commitInfo = git show -s --format="Author:`t%an (%ae)%nTitle:`t%s%nMerged:`t%ar" $commitHash
		If (0 -Eq $commitInfo.Count) {
			$commitInfo = @("Could not find commit information (consider running 'git fetch' first) !")
		}

		$additionalEntries = $commitInfo + $additionalEntries
	}

	Log $logType $message -additionalEntries $additionalEntries

	If ($isCurrent) {
		Log Success "Local master branch is currently on this commit"
	}

	If ($useLogDelimiter) {
		Log Info $logDelimiter
		LogNewLine
	}
}

function printAllRows() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement[]]$rows,

		[Parameter(Mandatory=$False)]
		[AllowNull()]
		[System.Xml.XmlElement]$rowToStopAt = $Null,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[Int[]]$validationColumns,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$projectBranch)
	[string]$currentCommit = GetCodeVersion -fullBranchName master -short
	For ([Int]$rowIndex = 0; $rowIndex -Lt $rows.Count; $rowIndex++) {
		$row = $rows[$rowIndex]
		[bool]$isLastRow = $row -Eq $rowToStopAt
		printRow -row $row -prefix "#$($rowIndex)/$($rows.Count)" -validationColumns $validationColumns -projectBranch $projectBranch -currentCommit $currentCommit -alwaysLog:$isLastRow
		If ($isLastRow) {
			break
		}
	}
}

$buildStatusTable = getBuildStatusTable -projectBranch $projectBranch -lookbackHours $lookbackHours

$parsedXml = [XML]$buildStatusTable
[System.Xml.XmlElement[]]$allRows = $parsedXml.table.tr
# Build rows are after the initial header rows
[Int]$tableHeaderRowIndex = 1
[Int]$firstBuildRowIndex = $tableHeaderRowIndex + 1
[string]$increaseLookbackMitigation = "increase `$lookbackHours value (currently $($lookbackHours) hours)"
[string]$resultRowsMitigation = "`nTry to:`n`t- $($increaseLookbackMitigation) or`n`t- decrease (if possible) test pass rate threshold (currently $($testPassRateThreshold)%) or`n`t- check the URI manually (is the logic in this script wrong?)."
If ($allRows.Length -Eq $firstBuildRowIndex) {
	ScriptFailure "Did not find any builds.$($resultRowsMitigation)"
} ElseIf (-Not ($allRows.Length -Gt $firstBuildRowIndex)) {
	ScriptFailure "Found only $($allRows.Length) row(s).$($resultRowsMitigation)"
}

[System.Xml.XmlElement[]]$tableHeaders = $allRows[$tableHeaderRowIndex].th
[System.Xml.XmlElement[]]$allBuildRows = $allRows | Select-Object -Skip $firstBuildRowIndex
# All rows are no longer required, we are only interested in the build rows going further
Remove-Variable -Name "allRows"

[HashTable]$validationResultColumnMap = @{}
If ($tableHeaders.Length -Gt $MandatoryColumnsTotal) {
	For ([Int]$ci = $MandatoryColumnsLeft; $ci -Lt $tableHeaders.Length - $MandatoryColumnsRight; $ci++) {
		[string]$validationResultName = $tableHeaders[$ci].InnerText
		If ([string]::IsNullOrEmpty($validationResultName)) {
			ScriptFailure "Test validation column #$($ci) has no header name"
		}

		[string]$statusNotScheduled = "Not Scheduled"
		If ($allBuildRows.Count -Eq ($allBuildRows | Where-Object { ($_.td.Length -Gt $ci) -And ($statusNotScheduled -Eq $_.td[$ci].InnerText) }).Count) {
			Log Warning "Test validation column #$($ci) [$($validationResultName)] has all $($allBuildRows.Count) row(s) with the status [$($statusNotScheduled)] in the past $($lookbackHours)h." `
				-additionalEntries @("Ignoring it from further checks.", "If you feel that this is a mistake then $($increaseLookbackMitigation).")
		} Else {
			$validationResultColumnMap[$ci] = $validationResultName
		}
	}
} Else {
	ScriptFailure "Found only $($tds.Length) columns, more than $($MandatoryColumnsTotal) mandatory columns expected"
}

If (0 -Eq $validationResultColumnMap.Keys.Count) {
	ScriptFailure "Did not find any test validation columns in $($allBuildRows.Count) build row(s).$($resultRowsMitigation)"
}

[Int[]]$validationColumns = $validationResultColumnMap.Keys | Sort-Object
Log Info "Found $($validationColumns.Count)/$($tableHeaders.Count) test validation columns:" `
	-additionalEntries ($validationColumns | ForEach-Object { "#$($_) [$($validationResultColumnMap[$_])]" })
# Test validation column map is no longer required, we are only interested in the indexes
Remove-Variable -Name "validationResultColumnMap"

[System.Xml.XmlElement[]]$allValidBuildRows = $allBuildRows | Where-Object { isRowValid -row $_ -validationColumns $validationColumns }
[System.Xml.XmlElement[]]$completedBuildRows = $allValidBuildRows | Where-Object {
	[string]$completedStatusesRegex = "((Passed)|(Failed))$($TestPassRateRegex)"
	[System.Xml.XmlElement[]]$row = $_
	[string[]]$completedValidationColumns = $validationColumns |
		Where-Object { $row.td[[Int]$_].InnerText -imatch $completedStatusesRegex }
	return $completedValidationColumns.Count -Eq $validationColumns.Count
}

If (0 -Eq $completedBuildRows.Count) {
	If ($printAllBuildInfo.IsPresent) {
		printAllRows -rows $allValidBuildRows -validationColumns $validationColumns -projectBranch $projectBranch
	}

	ScriptFailure "Did not find any rows with completed validations, $($allBuildRows.Count) rows are still in progress.`nPlease $($increaseLookbackMitigation)."
}

Log Info "Found $($completedBuildRows.Count)/$($allBuildRows.Count) build row(s) with completed validations."

[System.Xml.XmlElement[]]$matchingBuildRows = $completedBuildRows |
	Where-Object {
		(getLogTypeForRowBuild -row $_ -validationColumns $validationColumns) -Eq "Success" -And
		(isRowBuildTestPassRateSuccessful -row $_ -validationColumns $validationColumns)
	}
If ($Null -Eq $matchingBuildRows -Or $matchingBuildRows.Count -Eq 0) {
	If ($printAllBuildInfo.IsPresent) {
		printAllRows -rows $allValidBuildRows -validationColumns $validationColumns -projectBranch $projectBranch
	}

	# Try to find a build with most passed validations.
	[Int]$bestRowSuccessCount = 0
	[Int]$bestRowIndex = -1
	For ([Int]$i = 0; $i -Lt $allValidBuildRows.Count; $i++) {
		[string]$rowStatus = getRowStatus -row $allValidBuildRows[$i] -validationColumns $validationColumns
		[Int]$rowSuccessCount = (Select-String -Pattern "Passed" -InputObject $rowStatus -AllMatches).Matches.Count
		If ($rowSuccessCount -Gt $bestRowSuccessCount) {
			$bestRowIndex = $i
			$bestRowSuccessCount = $rowSuccessCount
		}
	}

	# As no build was fully successful - print the latest one with most passed validations.
	If ($bestRowIndex -Ge 0 -And $bestRowSuccessCount -Gt 0) {
		printRow -row $allValidBuildRows[$bestRowIndex] -prefix "Latest build row #$($bestRowIndex)/$($allBuildRows.Count) with $($bestRowSuccessCount)/$($validationColumns.Count) successful validation(s)" -validationColumns $validationColumns -projectBranch $projectBranch -alwaysLog
	}

	ScriptFailure "Did not find any successful builds out of $($allBuildRows.Count) build row(s).$($resultRowsMitigation)"
}

[System.Xml.XmlElement]$matchingBuildRow = $matchingBuildRows[0]

If (-Not [string]::IsNullOrWhiteSpace($targetBuildId)) {
	$matchingBuildRow = $matchingBuildRows | Where-Object { $_.td[0] -Ieq $targetBuildId } | Select-Object -First 1
	If ($Null -Eq $matchingBuildRow) {
		If ($printAllBuildInfo.IsPresent) {
			printAllRows -rows $allValidBuildRows -validationColumns $validationColumns -projectBranch $projectBranch
		}

		ScriptFailure "Did not find a successful [$($projectBranch)] build with ID #$($targetBuildId)"
	} Else {
		Log Success "Found a target build #$($targetBuildId), out of $($matchingBuildRows.Count)/$($allValidBuildRows.Count) successful [$($projectBranch)] builds`n"
	}
} Else {
	Log Success "Found $($matchingBuildRows.Count)/$($allValidBuildRows.Count) successful [$($projectBranch)] builds, taking first one`n"
}

# Matching rows variable is no longer required, we are only interested in the first matching row
Remove-Variable -Name "matchingBuildRows"

# Print all the build status rows
# - up to (and including) the first matching one
# - or all of them, if the appropriate flag is set
[System.Xml.XmlElement]$rowToStopPrintingAt = $matchingBuildRow
If ($printAllBuildInfo.IsPresent) {
	$rowToStopPrintingAt = $Null
}

printAllRows -rows $allValidBuildRows -rowToStopAt $rowToStopPrintingAt -validationColumns $validationColumns -projectBranch $projectBranch

[string]$commitHash = getGitCommitHash -row $matchingBuildRow -projectBranch $projectBranch

If ([string]::IsNullOrWhiteSpace($commitHash)) {
	ScriptFailure "Git commit hash not found for project [$($projectBranch)]"
}

If ($sync.IsPresent) {
	Log Warning "Syncing to $($commitHash)... Please restart the CoreXT console manually afterwards`n"
	& "$($PSScriptRoot)\..\git\merge_branch.ps1" -commit $commitHash -skipRemoteBranchInfoUpdate:($skipGitDetails.IsPresent -Or $global:isBranchInfoUpdated)

	If (ConfirmAction "Delete build folders (for a clean new build)") {
		delete_build_folders
	}
} Else {
	# Print commit hash to be used as a return value from this script,
	# potentially used in another script automation e.g. update source code to this commit
	return $commitHash
}
