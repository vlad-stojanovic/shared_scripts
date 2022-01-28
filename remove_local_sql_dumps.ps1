Param(
	[Parameter(Mandatory=$False)]
	[string[]]$sqlDumpFolders = @("$($env:USERPROFILE)\AppData\Local\CrashDumps", "$($env:USERPROFILE)\AppData\Local\Temp", "$($env:ProgramData)\Microsoft\Windows\WER\ReportQueue"),

	[Parameter(Mandatory=$False)]
	[ValidateNotNullOrEmpty()]
	[string]$sqlDumpFileFilter = "SQL*.dmp",

	[Parameter(Mandatory=$False)]
	[UInt16]$searchDepth = 1,

	[Parameter(Mandatory=$False)]
	[Validateset("path", "count", "size", "time")]
	[string]$dumpSortProperty = "time",

	[Parameter(Mandatory=$False)]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

# Search for SQL dumps
[HashTable]$resultMap = @{}
For ([UInt16]$dfI = 0; $dfI -Lt $sqlDumpFolders.Length; $dfI++) {
	[string]$sqlDumpFolderPath = Resolve-Path -Path $sqlDumpFolders[$dfI] -ErrorAction Ignore
	If ([string]::IsNullOrWhiteSpace($sqlDumpFolderPath)) {
		Log Error "Could not resolve path of #$($dfI+1)/$($sqlDumpFolders.Length) [$($sqlDumpFolders[$dfI])]"
		continue
	}

	[HashTable]$directoryMap = @{}
	Get-ChildItem -Path $sqlDumpFolderPath -Recurse -Depth $searchDepth -filter $sqlDumpFileFilter -File | ForEach-Object {
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

	$resultMap[$sqlDumpFolderPath] = $directoryMap
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

[string]$actionVerb = $Null
If ($dryRun.IsPresent) {
	$actionVerb = "Found"
} Else {
	$actionVerb = "Removed"
}

[UInt32]$totalDumpDirectoryCount = $resultObjects | ForEach-Object { $_.entries.Count } | Measure-Object -Sum | Select-Object -ExpandProperty Sum
If ($totalDumpDirectoryCount -Eq 0) {
	ScriptSuccess "No dump files $($actionVerb.ToLower()) in $($sqlDumpFolders.Length) root folders (search depth $($searchDepth))"
}

# Process all of the found dumps
ForEach ($resultObject in $resultObjects) {
	LogNewLine
	[string]$sqlDumpFolderPath = $resultObject.path
	[PSCustomObject[]]$dirObjects = $resultObject.entries
	If ($resultObject.count -Gt 0 -And $dirObjects.Count -Gt 0) {
		[UInt32]$dirDumpCount = $resultObject.count
		[UInt64]$dirDumpSize = $resultObject.size
		[DateTime]$dirLastDumpTime = $resultObject.time
		Log Info "Processing SQL dump folder [$($sqlDumpFolderPath)]"
		For ($doi = 0; $doi -Lt $dirObjects.Count; $doi++) {
			[string]$directoryPath = $dirObjects[$doi].path
			[UInt64]$dumpCount = $dirObjects[$doi].count
			[UInt64]$dumpSize = $dirObjects[$doi].size
			[DateTime]$dumpTime = $dirObjects[$doi].time

			If (-Not $dryRun.IsPresent) {
				# Ignore output from the command
				& "$($PSScriptRoot)/work/delete_objects_sync.ps1" -dirsToDelete @($directoryPath) | Out-Null
			}

			Log Warning "$($actionVerb) folder #$($doi + 1)/$($dirObjects.Count) [$($directoryPath)]" -additionalEntries @("with $($dumpCount) SQL dump file(s) of size $(GetSizeString -size $dumpSize -unit 'B' -decimalPoints $sizeDecimalPoints)", "latest dump occurred @ $($dumpTime.ToString($dateFormat))")
		}

		LogNewLine
		Log Warning "$($actionVerb) $($dirDumpCount) dump(s) of size $(GetSizeString -size $dirDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in [$($sqlDumpFolderPath)], latest @ $($dirLastDumpTime.ToString($dateFormat))"
	} Else {
		Log Success "No dump files $($actionVerb.ToLower()) in [$($sqlDumpFolderPath)]"
	}
}

LogNewLine
[UInt32]$totalDumpCount = $resultObjects | Measure-Object -Property "count" -Sum | Select-Object -ExpandProperty Sum
[UInt64]$totalDumpSize = $resultObjects | Measure-Object -Property "size" -Sum | Select-Object -ExpandProperty Sum
[DateTime]$totalLastDumpTime = $resultObjects | Measure-Object -Property "time" -Maximum | Select-Object -ExpandProperty Maximum
Log Warning "Total $($totalDumpCount) dump(s) $($actionVerb.ToLower()) of size $(GetSizeString -size $totalDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in $($totalDumpDirectoryCount) folders, latest @ $($totalLastDumpTime.ToString($dateFormat))"
