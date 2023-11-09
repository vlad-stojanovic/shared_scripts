Param(
	[Parameter(Mandatory=$False)]
	[AllowEmptyCollection()]
	[string[]]$additionalDumpFolders = @(),

	[Parameter(Mandatory=$False)]
	[ValidateNotNullOrEmpty()]
	[string]$dumpFileFilter = "SQL*.*dmp",

	[Parameter(Mandatory=$False)]
	[UInt16]$searchDepth = 1,

	[Parameter(Mandatory=$False)]
	[Validateset("path", "count", "size", "time")]
	[string]$dumpSortProperty = "time",

	[Parameter(Mandatory=$False)]
	[ValidateSet("delete", "list", "open")]
	[string]$action = "list")

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

[string[]]$dumpFolders = @(
	, "$($env:USERPROFILE)\AppData\Local\CrashDumps"
	, "$($env:USERPROFILE)\AppData\Local\Temp"
	, "$($env:ProgramData)\Microsoft\Windows\WER\ReportQueue")
If ($additionalDumpFolders.Count -Gt 0) {
	$dumpFolders += $additionalDumpFolders
}

# Search for dumps
[HashTable]$resultMap = @{}
For ([UInt16]$dfI = 0; $dfI -Lt $dumpFolders.Length; $dfI++) {
	[string]$dumpFolderPath = Resolve-Path -Path $dumpFolders[$dfI] -ErrorAction Ignore
	If ([string]::IsNullOrWhiteSpace($dumpFolderPath)) {
		Log Error "Could not resolve path of #$($dfI+1)/$($dumpFolders.Length) [$($dumpFolders[$dfI])]"
		continue
	}

	[HashTable]$directoryMap = @{}
	Get-ChildItem -Path $dumpFolderPath -Recurse -Depth $searchDepth -filter $dumpFileFilter -File | ForEach-Object {
		[string]$directoryPath = $_.Directory.FullName
		[PSCustomObject]$dirObject = $directoryMap[$directoryPath]
		If ($Null -Ne $dirObject) {
			$dirObject.count++
			$dirObject.size += $_.Length
			# Take the latest creation time
			If ($dirObject.time -Lt $_.CreationTime) {
				$dirObject.time = $_.CreationTime
			}
		} Else {
			$directoryMap[$directoryPath] = [PSCustomObject]@{ "count" = 1; "size" = $_.Length; "time" = $_.CreationTime; "path" = $directoryPath }
		}
	}

	$resultMap[$dumpFolderPath] = $directoryMap
}

[PSCustomObject[]]$resultObjects = $resultMap.Keys |
	ForEach-Object {
		[PSCustomObject[]]$dirObjects = $resultMap[$_].Values | Sort-Object -Property $dumpSortProperty
		return [PSCustomObject]@{
			"path" = $_
			"count" = $dirObjects | Measure-Object -Property "count" -Sum | Select-Object -ExpandProperty Sum
			"size" = $dirObjects | Measure-Object -Property "size" -Sum | Select-Object -ExpandProperty Sum
			"time" = $dirObjects | Measure-Object -Property "time" -Maximum | Select-Object -ExpandProperty Maximum
			"entries" = $dirObjects
		}
	} |
	Sort-Object -Property $dumpSortProperty
Remove-Variable -Name resultMap

[string]$dateFormat = "yyyy-MM-dd HH:mm:ss"
[Byte]$sizeDecimalPoints = 1

[string]$actionVerb = switch ($action) {
	"delete" { "Removed" }
	default { "Found" }
}

[UInt32]$totalDumpDirectoryCount = $resultObjects | ForEach-Object { $_.entries.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
If ($totalDumpDirectoryCount -Eq 0) {
	ScriptSuccess "No dump files $($actionVerb.ToLower()) in $($dumpFolders.Length) root folders (search depth $($searchDepth))"
}

# Process all of the found dumps
[PSCustomObject]$lastDumpEntry = $Null
ForEach ($resultObject in $resultObjects) {
	LogNewLine
	[string]$dumpFolderPath = $resultObject.path
	[PSCustomObject[]]$dirObjects = $resultObject.entries
	If ($resultObject.count -Gt 0 -And $dirObjects.Count -Gt 0) {
		[UInt32]$dirDumpCount = $resultObject.count
		[UInt64]$dirDumpSize = $resultObject.size
		[DateTime]$dirLastDumpTime = $resultObject.time
		Log Info "Processing dump folder [$($dumpFolderPath)]"
		For ($doi = 0; $doi -Lt $dirObjects.Count; $doi++) {
			$lastDumpEntry = $dirObjects[$doi]
			[string]$directoryPath = $dirObjects[$doi].path
			[UInt64]$dumpCount = $dirObjects[$doi].count
			[UInt64]$dumpSize = $dirObjects[$doi].size
			[DateTime]$dumpTime = $dirObjects[$doi].time

			If ($action -IEq "delete") {
				# Ignore output from the command
				& "$($PSScriptRoot)/work/delete_objects_sync.ps1" -objectsToDelete @($directoryPath) | Out-Null
			}

			Log Warning "$($actionVerb) folder #$($doi + 1)/$($dirObjects.Count) [$($directoryPath)]" -additionalEntries @("with $($dumpCount) dump file(s) of size $(GetSizeString -size $dumpSize -unit 'B' -decimalPoints $sizeDecimalPoints)", "latest dump occurred @ $($dumpTime.ToString($dateFormat))")
		}

		LogNewLine
		Log Warning "$($actionVerb) $($dirDumpCount) dump(s) of size $(GetSizeString -size $dirDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in [$($dumpFolderPath)], latest @ $($dirLastDumpTime.ToString($dateFormat))"
	} Else {
		Log Success "No dump files $($actionVerb.ToLower()) in [$($dumpFolderPath)]"
	}
}

If ($action -IEq "open" -And $Null -Ne $lastDumpEntry) {
	LogNewLine
	Log Info "Opening last dump (sorted by $($dumpSortProperty)) directory @ [$($lastDumpEntry.path)]"
	Invoke-Item -Path $lastDumpEntry.path
}

LogNewLine
[UInt32]$totalDumpCount = $resultObjects | Measure-Object -Property "count" -Sum | Select-Object -ExpandProperty Sum
[UInt64]$totalDumpSize = $resultObjects | Measure-Object -Property "size" -Sum | Select-Object -ExpandProperty Sum
[DateTime]$totalLastDumpTime = $resultObjects | Measure-Object -Property "time" -Maximum | Select-Object -ExpandProperty Maximum
Log Warning "Total $($totalDumpCount) dump(s) $($actionVerb.ToLower()) of size $(GetSizeString -size $totalDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in $($totalDumpDirectoryCount) folders, latest @ $($totalLastDumpTime.ToString($dateFormat))"
