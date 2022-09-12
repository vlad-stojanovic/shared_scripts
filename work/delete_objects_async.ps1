Param(
	[Parameter(Mandatory=$True)]
	[string[]]$objectsToDelete,

	[Parameter(Mandatory=$False)]
	[string]$rootDir,

	[Parameter(Mandatory=$False)]
	[UInt16]$waitTimeS = 5)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[System.Diagnostics.StopWatch]$stopWatch = [System.Diagnostics.StopWatch]::StartNew()

$jobMap = @{}

ForEach ($object in $objectsToDelete) {
	[string]$targetObject = $object
	If (-Not [string]::IsNullOrWhiteSpace($rootDir)) {
		$targetObject = Join-Path -Path $rootDir -ChildPath $object
	}

	If (Test-Path -Path $targetObject){
		Log Warning "Deleting entry [$($targetObject)]"

		$job = Start-Job -ScriptBlock {
				Param([string]$targetObject, [string]$deleteScriptPath)
				& $deleteScriptPath -objectsToDelete @($targetObject)
			} -ArgumentList @($targetObject, "$($PSScriptRoot)\delete_objects_sync.ps1") -Name "Removal of [$targetObject] object"
		$jobMap.Add($targetObject, $job.Id)
	} Else {
		Log Verbose "Object does not exist [$($targetObject)]"
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

	[string[]]$objects = $jobMap.Keys
	ForEach ($object in $objects) {
		$job = Get-Job -Id $jobMap[$object]
		If ("Completed" -Eq $job.State) {
			Log Success "Done with [$($object)] after $(GetStopWatchDuration -stopWatch $stopWatch)" -indentLevel 1

			# Clean any remaining jobs with the same name
			# that might be previously started but not removed.
			Remove-Job -Name $job.Name -ErrorAction SilentlyContinue
			$jobMap.Remove($object)
		} Else {
			Log Verbose "Deletion of [$($object)] is in state: $($job.State), for job '$($job.Name)'" -indentLevel 1
		}
	}
} While ($jobMap.Count -Gt 0)

LogNewLine
Log Success "Deletion finished in $(GetStopWatchDuration -stopWatch $stopWatch -stop)"