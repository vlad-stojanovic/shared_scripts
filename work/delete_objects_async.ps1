Param(
	[Parameter(Mandatory=$True)]
	[string[]]$dirsToDelete,

	[Parameter(Mandatory=$False)]
	[string]$rootDir,

	[Parameter(Mandatory=$False)]
	[UInt16]$waitTimeS = 5)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[System.Diagnostics.StopWatch]$stopWatch = [System.Diagnostics.StopWatch]::StartNew()

$jobMap = @{}

ForEach ($dir in $dirsToDelete) {
	[string]$targetDir = $dir
	If (-Not [string]::IsNullOrWhiteSpace($rootDir)) {
		$targetDir = Join-Path -Path $rootDir -ChildPath $dir
	}

	If (Test-Path -Path $targetDir -PathType Container){
		Log Warning "Deleting entries from [$($targetDir)] directory"

		$job = Start-Job -ScriptBlock {
				Param([string]$targetDir, [string]$deleteScriptPath)
				& $deleteScriptPath -dirsToDelete @($targetDir)
			} -ArgumentList @($targetDir, "$($PSScriptRoot)\delete_objects_sync.ps1") -Name "Removal of [$targetDir] directory"
		$jobMap.Add($targetDir, $job.Id)
	} Else {
		Log Verbose "Folder does not exist [$($targetDir)]"
	}
}

If ($jobMap.Count -Eq 0) {
	LogNewLine
	ScriptSuccess "No deletion jobs started"
}

Do {
	LogNewLine
	Log Info "Checking status of $($jobMap.Count) remaining deletion job(s) in $($waitTimeS) seconds (elapsed time $(GetStopWatchDuration -stopWatch $stopWatch))"
	Start-Sleep -Seconds $waitTimeS

	[string[]]$dirs = $jobMap.Keys
	ForEach ($dir in $dirs) {
		$job = Get-Job -Id $jobMap[$dir]
		If ("Completed" -Eq $job.State) {
			Log Success "Done with [$($dir)] after $(GetStopWatchDuration -stopWatch $stopWatch)" -indentLevel 1

			# Clean any remaining jobs with the same name
			# that might be previously started but not removed.
			Remove-Job -Name $job.Name -ErrorAction SilentlyContinue
			$jobMap.Remove($dir)
		} Else {
			Log Verbose "Deletion of [$($dir)] is in state: $($job.State), for job '$($job.Name)'" -indentLevel 1
		}
	}
} While ($jobMap.Count -Gt 0)

LogNewLine
Log Success "Deletion finished in $(GetStopWatchDuration -stopWatch $stopWatch -stop)"