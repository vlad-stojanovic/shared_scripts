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
		LogError "Could not resolve path of #$($dfI+1)/$($sqlDumpFolders.Length) [$($sqlDumpFolders[$dfI])]"
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

# Process all of the found dumps
ForEach ($sqlDumpFolderPath in ($resultMap.Keys | Sort-Object)) {
	LogNewLine
	[HashTable]$directoryMap = $resultMap[$sqlDumpFolderPath]
	If ($directoryMap.Keys.Count -Gt 0) {
		[UInt32]$directoryCount = 0
		[UInt32]$totalDumpCount = 0
		[UInt64]$totalDumpSize = 0
		[DateTime]$totalLastDumpTime = [DateTime]::MinValue
		LogInfo "Processing SQL dump folder [$($sqlDumpFolderPath)]"
		ForEach ($directoryPath in ($directoryMap.Keys | Sort-Object)) {
			[UInt64]$dumpCount = $directoryMap[$directoryPath].count
			[UInt64]$dumpSize = $directoryMap[$directoryPath].size
			[DateTime]$dumpTime = $directoryMap[$directoryPath].time
			$directoryCount++
			$totalDumpCount += $dumpCount
			$totalDumpSize += $dumpSize
			If ($totalLastDumpTime -Lt $dumpTime) {
				$totalLastDumpTime = $dumpTime
			}

			[string]$directoryInfo = "folder #$($directoryCount)/$($directoryMap.Keys.Count) [$($directoryPath)]`n`twith $($dumpCount) SQL dump file(s) of size $(GetSizeString -size $dumpSize -unit 'B'), latest @ $($dumpTime.ToString($dateFormat))"
			If ($dryRun.IsPresent) {
				LogWarning "Found $($directoryInfo)"
			} Else {
				LogWarning "Removing $($directoryInfo)"
				# Ignore output from the command
				& "$($PSScriptRoot)/work/delete_objects_sync.ps1" -dirsToDelete @($directoryPath) | Out-Null
			}
		}

		LogNewLine
		LogWarning "Total $($totalDumpCount) dump(s) of size $(GetSizeString -size $totalDumpSize -unit 'B') in [$($sqlDumpFolderPath)], latest @ $($totalLastDumpTime.ToString($dateFormat))"
	} Else {
		LogSuccess "No dump files found in [$($sqlDumpFolderPath)] (search depth $($searchDepth))"
	}
}