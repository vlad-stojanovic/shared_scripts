Param(
	[Parameter(Mandatory=$False, HelpMessage="Project to search LKGC (last-known-good-changeset) for")]
	[ValidateSet("DS_MAIN", "DS_MAIN_DEV", "DS_MAIN_DEV_GIT")]
	[string]$project = "DS_MAIN_DEV_GIT",

	[Parameter(Mandatory=$False, HelpMessage="Relevant aliases whose builds should be highlighted")]
	[string[]]$relevantAliases = @("AVAdmin", $env:USERNAME),

	[Parameter(Mandatory=$False, HelpMessage="Number of past hours (to look back) in the validation report")]
	[ValidateScript({ $_ -Ge 12 })]
	[UInt16]$lookbackHours = 24,

	[Parameter(Mandatory=$False, HelpMessage="Target build ID to be used (if successful) - value in the (usually leftmost) column named [ID] in the validation report)")]
	[string]$targetBuildId = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Perform the sync to the LGKC (i.e. the commit ID discovered, if available)")]
	[switch]$sync,

	[Parameter(Mandatory=$False, HelpMessage="Ignore recent cached contents (by default reused for an hour) of the validation report")]
	[switch]$ignoreCache,

	[Parameter(Mandatory=$False, HelpMessage="Print all rows/entries containing build information in the validation report")]
	[switch]$printAllBuildInfo,

	[Parameter(Mandatory=$False, HelpMessage="Show debug logs (internal to this script)")]
	[switch]$showDebugLogs)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

$ErrorActionPreference = "Stop"

[string[]]$ValidProjects = @("DS_MAIN", "DS_MAIN_DEV", "DS_MAIN_DEV_GIT")

function getBuildStatusTable() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project,

		[Parameter(Mandatory=$True)]
		[UInt16]$lookbackHours)

	$cacheValidityInMinutes = 60;
	$cacheFilePath = Join-Path -Path $PSScriptRoot -ChildPath "cache/build_status_table_cache_$($project)_$($lookbackHours)h.txt"
	If (Test-Path -Path $cacheFilePath) {
		$creationTime = (Get-Item -Path $cacheFilePath).CreationTime
		$cacheFileContent = Get-Content -Path $cacheFilePath
		If ($creationTime -Gt (Get-Date).AddMinutes(-$cacheValidityInMinutes) -And
			(-Not [string]::IsNullOrWhitespace($cacheFileContent))) {
			If (-Not $ignoreCache.IsPresent) {
				Log Info "[$($project)] Using contents from [$($cacheFilePath)] created @ [$($creationTime)]"
				return $cacheFileContent
			} Else {
				Log Warning "[$($project)] Ignoring valid cache @ [$($cacheFilePath)]"
			}
		} Else {
			Log Warning "[$($project)] Removing stale/empty cache @ [$($cacheFilePath)]"
			Remove-Item -Path $cacheFilePath
		}
	}

	[string]$baseUri = "https://troubleshooter.redmond.corp.microsoft.com/CVReport.aspx"

	[string]$targetUri = "$($baseUri)?LastHours=$($lookbackHours)&PassRate=0&Branch=$($project)&Title=$($project)&Key=14&Dim=0"

	Log Verbose "[$($project)] Downloading DS CI status from [$($targetUri)]"
	$html = (Invoke-WebRequest -Uri $targetUri).Content

	Log Verbose "[$($project)] Removing all new lines and link (<a>) tags to avoid XML parsing errors"
	$htmlMin = $html -replace "(\r?\n)|(</?a[^>]*>)", ""

	$tableMatch = Select-String -InputObject $htmlMin -Pattern "<table[^>]*>.*</table>"
	$buildStatusTable = $tableMatch.Matches[0].Groups[0].Value
	Log Info "[$($project)] Caching values @ [$($cacheFilePath)] reusable for $($cacheValidityInMinutes) minutes"
	CreateFileIfNotExists -filePath $cacheFilePath
	$buildStatusTable | Out-File -FilePath $cacheFilePath
	return $buildStatusTable
}

function getGitCommitHash() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)

	switch ($project) {
		"DS_MAIN" { return $Null }
		"DS_MAIN_DEV" { return $row.td[1] }
		"DS_MAIN_DEV_GIT" { return $row.td[2] }
		Default { return $Null }
	}
}

[int[]]$global:StatusColumns = switch ($project) {
	"DS_MAIN" { @(10, 13, 14); break }
	"DS_MAIN_DEV" { @(10, 13, 14); break }
	"DS_MAIN_DEV_GIT" { @(9, 10, 11, 12, 13, 14); break }
	DEFAULT { ScriptFailure "Invalid project $($project)"; break }
}
[string]$global:StatusDelimiter = " / "
[string]$global:ValidRowStatus = ($global:StatusColumns | ForEach-Object { "Passed" }) -join $global:StatusDelimiter

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
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)
	[string[]]$statuses = $global:StatusColumns | ForEach-Object { $row.td[$_].InnerText }
	ForEach ($status in $statuses) {
		If ([string]::IsNullOrWhiteSpace($status)) {
			return $Null
		}
	}
	return $statuses -join " / "
}

function isRowValid() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)

	[bool]$isRowValid = ($Null -Ne $row.td -And
		$row.td.Count -Gt [System.Linq.Enumerable]::Max($global:StatusColumns) -And
		(-Not [string]::IsNullOrWhiteSpace((getRowStatus -row $row -project $project))))
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

function getLogTypeForRowBuild() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)
	[string]$rowStatus = getRowStatus -row $row -project $project
	[string]$logType = "Warning"
	[bool]$isSuccessfulBuild = $rowStatus -Eq $global:ValidRowStatus
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
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)

	$tds = $row.td;
	[string]$id = $tds[0]
	[string]$commitHash = getGitCommitHash -row $row -project $project
	[string]$descendantId = $tds[3]
	[string]$descendantType = $tds[4]
	[string]$time = $tds[5]
	[string]$alias = $tds[6]
	[string]$status = getRowStatus -row $row -project $project
	[string]$latency = $tds[[System.Linq.Enumerable]::Max($global:StatusColumns) + 1]

	[string]$logDelimiter = "# # # # # # # # # # # # # # # # # # # # #"
	[bool]$useLogDelimiter = (-Not [string]::IsNullOrEmpty($alias)) -And ($relevantAliases -contains $alias)
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

	[string]$logType = getLogTypeForRowBuild -row $row -project $project
	Log $logType $message -additionalEntries @("Status: $($status)", "Descendant: $($descendantInfo)", "Commit hash [$($commitHash)]")

	If ($useLogDelimiter) {
		Log Info $logDelimiter
		LogNewLine
	}
}

$buildStatusTable = getBuildStatusTable -project $project -lookbackHours $lookbackHours

$parsedXml = [XML]$buildStatusTable
[System.Xml.XmlElement[]]$allValidRows = $parsedXml.table.tr | Where-Object { isRowValid -row $_  -project $project }
[System.Xml.XmlElement[]]$matchingRows = $allValidRows | Where-Object { (getLogTypeForRowBuild -row $_ -project $project) -Eq "Success" }
If ($Null -Eq $matchingRows -Or $matchingRows.Count -Eq 0) {
	ScriptFailure "Did not find any successful builds, try increasing the lookback period or checking the URI manually (is the logic in this script wrong?)."
}

[System.Xml.XmlElement]$matchingRow = $matchingRows[0]

If (-Not [string]::IsNullOrWhiteSpace($targetBuildId)) {
	$matchingRow = $matchingRows | Where-Object { $_.td[0] -Ieq $targetBuildId } | Select-Object -First 1
	If ($Null -Eq $matchingRow) {
		ScriptFailure "Did not find a successful [$($project)] build with ID #$($targetBuildId)"
	} Else {
		Log Success "Found a target build #$($targetBuildId), out of $($matchingRows.Count)/$($allValidRows.Count) successful [$($project)] builds`n"
	}
} Else {
	Log Success "Found $($matchingRows.Count)/$($allValidRows.Count) successful [$($project)] builds, taking first one`n"
}

# Matching rows variable is no longer required, we are only interested in the first matching row
Remove-Variable -Name "matchingRows"

# Print all the build status rows
# - up to (and including) the first matching one
# - or all of them, if the appropriate flag is set
For ($rowIndex = 0; $rowIndex -Lt $allValidRows.Count; $rowIndex++) {
	$row = $allValidRows[$rowIndex]
	printRow -row $row -prefix "#$($rowIndex)/$($allValidRows.Count)" -project $project
	If ((-Not $printAllBuildInfo.IsPresent) -And ($row -Eq $matchingRow)) {
		break;
	}
}

[string]$commitHash = getGitCommitHash -row $matchingRow -project $project

If ([string]::IsNullOrWhiteSpace($commitHash)) {
	ScriptFailure "Git commit hash not found for project [$($project)]"
}

If ($sync.IsPresent) {
	Log Warning "Syncing to $($commitHash)... Please restart the CoreXT console manually afterwards`n"
	& "$($PSScriptRoot)\git\merge_branch.ps1" -commit $commitHash

	If (ConfirmAction "Delete build folders (for a clean new build)") {
		delete_build_folders
	}
} Else {
	# Print commit hash to be used as a return value from this script,
	# potentially used in another script automation e.g. update source code to this commit
	return $commitHash
}
