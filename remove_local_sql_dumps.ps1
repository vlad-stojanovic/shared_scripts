Param(
	[Parameter(Mandatory=$False)]
	[string[]]$sqlDumpFolders = @("$($env:USERPROFILE)\AppData\Local\CrashDumps", "$($env:USERPROFILE)\AppData\Local\Temp", "$($env:ProgramData)\Microsoft\Windows\WER\ReportQueue"),

	[Parameter(Mandatory=$False)]
	[ValidateNotNullOrEmpty()]
	[string]$sqlDumpFileFilter = "SQL*.dmp",

	[Parameter(Mandatory=$False)]
	[UInt16]$searchDepth = 1,

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
	Get-ChildItem -Path $sqlDumpFolderPath -Recurse -Depth $searchDepth -filter $sqlDumpFileFilter -File |
		ForEach-Object {
			[string]$directoryPath = $_.Directory.FullName
			[HashTable]$map = $directoryMap[$directoryPath]
			If ($Null -Ne $map) {
				$map.count++
				$map.size += $_.Length
				# Take the latest creation time
				If ($map.time -Lt $_.CreationTime) {
					$map.time = $_.CreationTime
				}
			} Else {
				$directoryMap[$directoryPath] = @{ "count" = 1; "size" = $_.Length; "time" = $_.CreationTime }
			}
		}

	$resultMap[$sqlDumpFolderPath] = $directoryMap
}

[string]$dateFormat = "yyyy-MM-dd HH:mm:ss"
[Byte]$sizeDecimalPoints = 1

[string]$actionVerb = $Null
If ($dryRun.IsPresent) {
	$actionVerb = "Found"
} Else {
	$actionVerb = "Removed"
}

[UInt32]$totalDumpDirectoryCount = 0
[UInt32]$totalDumpCount = 0
[UInt64]$totalDumpSize = 0
[DateTime]$totalLastDumpTime = [DateTime]::MinValue

# Process all of the found dumps
ForEach ($sqlDumpFolderPath in ($resultMap.Keys | Sort-Object)) {
	LogNewLine
	[HashTable]$directoryMap = $resultMap[$sqlDumpFolderPath]
	If ($directoryMap.Keys.Count -Gt 0) {
		[UInt32]$dirSubdirectoryCount = 0
		[UInt32]$dirDumpCount = 0
		[UInt64]$dirDumpSize = 0
		[DateTime]$dirLastDumpTime = [DateTime]::MinValue
		Log Info "Processing SQL dump folder [$($sqlDumpFolderPath)]"
		ForEach ($directoryPath in ($directoryMap.Keys | Sort-Object)) {
			[UInt64]$dumpCount = $directoryMap[$directoryPath].count
			[UInt64]$dumpSize = $directoryMap[$directoryPath].size
			[DateTime]$dumpTime = $directoryMap[$directoryPath].time
			$dirSubdirectoryCount++
			$dirDumpCount += $dumpCount
			$dirDumpSize += $dumpSize
			If ($dirLastDumpTime -Lt $dumpTime) {
				$dirLastDumpTime = $dumpTime
			}

			If (-Not $dryRun.IsPresent) {
				# Ignore output from the command
				& "$($PSScriptRoot)/work/delete_objects_sync.ps1" -dirsToDelete @($directoryPath) | Out-Null
			}

			Log Warning "$($actionVerb) folder #$($dirSubdirectoryCount)/$($directoryMap.Keys.Count) [$($directoryPath)]" -additionalEntries @("with $($dumpCount) SQL dump file(s) of size $(GetSizeString -size $dumpSize -unit 'B' -decimalPoints $sizeDecimalPoints)", "latest dump occurred @ $($dumpTime.ToString($dateFormat))")
		}

		LogNewLine
		Log Warning "$($actionVerb) $($dirDumpCount) dump(s) of size $(GetSizeString -size $dirDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in [$($sqlDumpFolderPath)], latest @ $($dirLastDumpTime.ToString($dateFormat))"

		$totalDumpDirectoryCount += $dirSubdirectoryCount
		$totalDumpCount += $dirDumpCount
		$totalDumpSize += $dirDumpSize
		If ($totalLastDumpTime -Lt $dirLastDumpTime) {
			$totalLastDumpTime = $dirLastDumpTime
		}
	} Else {
		Log Success "No dump files $($actionVerb.ToLower()) in [$($sqlDumpFolderPath)]"
	}
}

LogNewLine
If ($totalDumpCount -Gt 0) {
	Log Warning "Total $($totalDumpCount) dump(s) $($actionVerb.ToLower()) of size $(GetSizeString -size $totalDumpSize -unit 'B' -decimalPoints $sizeDecimalPoints) in $($totalDumpDirectoryCount) folders, latest @ $($totalLastDumpTime.ToString($dateFormat))"
} Else {
	Log Success "No dump files $($actionVerb.ToLower()) in $($sqlDumpFolders.Length) root folders (search depth $($searchDepth))"
}