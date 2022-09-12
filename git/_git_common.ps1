# File includes Git helper functions that may exit the calling scope (e.g. in case of failures)
# and are therefore not safe to be used in (alias) functions, but only in scripts.

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# Include safe Git helper functions
. "$($PSScriptRoot)/_git_common_safe.ps1"

function RunGitCommand() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Git command to be executed")]
		[ValidateNotNullOrEmpty()]
		[string]$gitCommand,

		[Parameter(Mandatory=$False, HelpMessage="Git command parameters")]
		[AllowNull()]
		[string[]]$parameters = $Null,

		[Parameter(Mandatory=$False, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$changedFileCount = 0)
	# Exit the script on command failure.
	[bool]$execStatus = RunGitCommandSafely -gitCommand $gitCommand -parameters $parameters -changedFileCount $changedFileCount
	If (-Not $execStatus) {
		ScriptFailure "Git $($gitCommand) failed"
	}

}

function UpdateBranchesInfoFromRemote() {
	[OutputType([System.Void])]
	Param()
	[UInt16]$jobCount = 1
	If ([System.Environment]::ProcessorCount -Ge 3) {
		# Take 2/3 of the available processors
		$jobCount = [System.Environment]::ProcessorCount * 2 / 3
	}

	Log Warning "If 'git fetch' takes a long time - best to first" -additionalEntries @(
		"clean up loose objects via 'git prune' or",
		"optimize the local repo via 'git gc'") -entryPrefix "- "
	RunGitCommand -gitCommand "fetch" -parameters @("-pq", "--jobs=$($jobCount)")
}

function GetCurrentBranchName() {
	[OutputType([string])]
	Param()
	[string]$currentBranchName = GetCurrentBranchNameSafely
	If ([string]::IsNullOrWhiteSpace($currentBranchName)) {
		ScriptFailure "Unable to get current Git branch name"
	}

	return $currentBranchName;
}

function StashChangesAndGetChangedFileCount() {
	[OutputType([Int])]
	Param()
	[string[]]$allChangedFiles = git status -su | ForEach-Object { $_.Trim() }
	If ($allChangedFiles.Count -Eq 0 ) {
		Log Success "No files changed -> no stashing"
	} Else {
		[int]$maxEntries = 8
		[string[]]$additionalEntries = $allChangedFiles
		If ($allChangedFiles.Count -Gt $maxEntries) {
			$additionalEntries = ($allChangedFiles | Select-Object -First ($maxEntries - 1)) + "and $($allChangedFiles.Count - $maxEntries + 1) more..."
		}

		Log Warning "Stashing $($allChangedFiles.Count) changed files" -additionalEntries $additionalEntries -entryPrefix "- "
		RunGitCommand -gitCommand "stash" -parameters @("--include-untracked")
	}

	return $allChangedFiles.Count;
}

function UnstashChanges() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$False, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$changedFileCount)
	If ($changedFileCount -Gt 0) {
		RunGitCommand -gitCommand "stash" -parameters @("pop") -changedFileCount $changedFileCount
	}
}
