Param(
	[Parameter(Mandatory=$False)]
	[ValidateSet("DS_MAIN", "DS_MAIN_DEV", "DS_MAIN_DEV_GIT")]
	[string]$project = "DS_MAIN_DEV",

	[Parameter(Mandatory=$False)]
	[ValidateScript({ $_ -Ge 12 })]
	[UInt16]$lookbackHours = 24,

	[Parameter(Mandatory=$False)]
	[string]$targetBuildId = $Null,

	[Parameter(Mandatory=$False)]
	[switch]$sync,

	[Parameter(Mandatory=$False)]
	[switch]$ignoreCache)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

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
	$cacheFilePath = Join-Path -Path $PSScriptRoot -ChildPath "build_status_table_cache_$($project)_$($lookbackHours)h.txt"
	If (Test-Path -Path $cacheFilePath) {
		$creationTime = (Get-Item -Path $cacheFilePath).CreationTime
		$cacheFileContent = Get-Content -Path $cacheFilePath
		If ($creationTime -Gt (Get-Date).AddMinutes(-$cacheValidityInMinutes) -And
			(-Not [string]::IsNullOrWhitespace($cacheFileContent))) {
			If (-Not $ignoreCache.IsPresent) {
				LogInfo "[$($project)] Using contents from [$($cacheFilePath)] created @ [$($creationTime)]"
				return $cacheFileContent
			} Else {
				LogWarning "[$($project)] Ignoring valid cache @ [$($cacheFilePath)]"
			}
		} Else {
			LogWarning "[$($project)] Removing stale/empty cache @ [$($cacheFilePath)]"
			Remove-Item -Path $cacheFilePath
		}
	}

	[string]$baseUri = "https://troubleshooter.redmond.corp.microsoft.com/CVReport.aspx"

	[string]$targetUri = "$($baseUri)?LastHours=$($lookbackHours)&PassRate=0&Branch=$($project)&Title=$($project)&Key=14"

	LogInfo "[$($project)] Downloading DS CI status from [$($targetUri)]"
	$html = (Invoke-WebRequest -Uri $targetUri).Content

	LogInfo "[$($project)] Removing all new lines and link (<a>) tags to avoid XML parsing errors"
	$htmlMin = $html -replace "(\r?\n)|(</?a[^>]*>)", ""

	$tableMatch = Select-String -InputObject $htmlMin -Pattern "<table[^>]*>.*</table>"
	$buildStatusTable = $tableMatch.Matches[0].Groups[0].Value
	LogInfo "[$($project)] Caching values @ [$($cacheFilePath)] reusable for $($cacheValidityInMinutes) minutes"
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

function isRowValid() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)

	return ($Null -Ne $row.td -And
		$row.td.Count -Ge 12 -And
		(-Not [string]::IsNullOrWhiteSpace((getRowStatus -row $row -project $project))))
}

[string]$ValidRowStatus = "Passed / Passed / Passed"

function getRowStatus() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)
	
	[string[]]$statuses = @($row.td[9].InnerText, $row.td[10].InnerText, $row.td[11].InnerText)
	ForEach ($status in $statuses) {
		If ([string]::IsNullOrWhiteSpace($status)) {
			return $Null
		}
	}
	return $statuses -join " / "
}

function isRowForASuccessfulBuild() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Xml.XmlElement]$row,

		[Parameter(Mandatory=$True)]
		[ValidateScript({ $ValidProjects.Contains($_) })]
		[string]$project)

	return (getRowStatus -row $row -project $project) -Eq $ValidRowStatus;
}

function printRow() {
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
	[string]$time = $tds[5]
	[string]$alias = $tds[6]
	[string]$status = getRowStatus -row $row -project $project
	[string]$latency = $tds[12]

	[string]$message = "$($prefix): ID #$($id) by [$($alias)] @ [$($time)], E2E latency: $($latency)`n`tStatus: $($status)`n`tCommit hash [$($commitHash)]"
	If (isRowForASuccessfulBuild -row $row -project $project) {
		LogSuccess $message
	} Else {
		LogWarning $message
	}
}

$buildStatusTable = getBuildStatusTable -project $project -lookbackHours $lookbackHours

$parsedXml = [XML]$buildStatusTable
[System.Xml.XmlElement[]]$allValidRows = $parsedXml.table.tr | `
	Where-Object { isRowValid -row $_  -project $project }
[System.Xml.XmlElement[]]$matchingRows = $allValidRows | `
	Where-Object { isRowForASuccessfulBuild -row $_ -project $project }
If ($Null -Eq $matchingRows -Or $matchingRows.Count -Eq 0) {
	ScriptFailure "Did not find any successful builds, is the logic in this script wrong?"
}

[System.Xml.XmlElement]$matchingRow = $matchingRows[0]

If (-Not [string]::IsNullOrWhiteSpace($targetBuildId)) {
	$matchingRow = $matchingRows | Where-Object { $_.td[0] -Ieq $targetBuildId } | Select-Object -First 1
	If ($Null -Eq $matchingRow) {
		ScriptFailure "Did not find a successful [$($project)] build with ID #$($targetBuildId)"
	} Else {
		LogSuccess "Found a target build #$($targetBuildId), out of $($matchingRows.Count)/$($allValidRows.Count) successful [$($project)] builds`n"
	}
} Else {
	LogSuccess "Found $($matchingRows.Count)/$($allValidRows.Count) successful [$($project)] builds, taking first one`n"
}

# Matching rows variable is no longer required, we are only interested in the first matching row
Remove-Variable -Name "matchingRows"

# Print all the build status rows up to (and including) the first matching one
For ($rowIndex = 0; $rowIndex -Lt $allValidRows.Count; $rowIndex++) {
	$row = $allValidRows[$rowIndex]
	printRow -row $row -prefix "#$($rowIndex)/$($allValidRows.Count)" -project $project
	If ($row -Eq $matchingRow) {
		break;
	}
}

[string]$commitHash = getGitCommitHash -row $matchingRow -project $project

If ([string]::IsNullOrWhiteSpace($commitHash)) {
	ScriptFailure "Git commit hash not found for project [$($project)]"
}

If ($sync.IsPresent) {
	LogInfo "Syncing to $($commitHash)...`n"
	Invoke-Expression "$($PSScriptRoot)\git\merge_branch.ps1 -commit $($commitHash)"
} Else {
	# Print commit hash to be used as a return value from this script,
	# potentially used in another script automation e.g. update source code to this commit
	return $commitHash
}