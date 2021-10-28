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
		LogWarning "Deleting entries from [$($targetDir)] directory"
		$job = Start-Job -ScriptBlock {
				Param([string]$targetDir)
				Remove-Item -Path $targetDir -Recurse -Force -ErrorAction SilentlyContinue
			} -ArgumentList $targetDir -Name "Removal of [$($targetDir)] directory"
		$jobMap.Add($dir, $job.Id)
	} Else {
		LogInfo "Folder does not exist [$($targetDir)]"
	}
}

If ($jobMap.Count -Eq 0) {
	LogNewLine
	ScriptExit -exitStatus 0 -message "No deletion jobs started"
}

Do {
	LogNewLine
	LogInfo "Checking status of $($jobMap.Count) remaining deletion job(s) in $($waitTimeS) seconds"
	Start-Sleep -Seconds $waitTimeS

	[string[]]$dirs = $jobMap.Keys
	ForEach ($dir in $dirs) {
		$job = Get-Job -Id $jobMap[$dir]
		If ("Completed" -Eq $job.State) {
			LogSuccess "Done with [$($dir)] after $($stopWatch.Elapsed.ToString('hh\:mm\:ss'))"
			$jobResult = Receive-Job -Job $job -AutoRemoveJob -Wait
			If (-Not [string]::IsNullOrWhiteSpace($jobResult)) {
				LogInfo "Results:`n$($jobResult)"
			}
			# Clean any remaining jobs with the same name
			# that might be previously started but not removed.
			Remove-Job -Name $job.Name -ErrorAction SilentlyContinue
			$jobMap.Remove($dir)
		} Else {
			LogInfo "Deletion of [$($dir)] is in state: $($job.State)"
		}
	}
} While ($jobMap.Count -Gt 0)

$stopWatch.Stop()
LogNewLine
LogSuccess "Deletion finished in $($stopWatch.Elapsed.ToString('hh\:mm\:ss'))"