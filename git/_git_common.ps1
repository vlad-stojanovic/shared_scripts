# File includes Git helper functions that may exit the calling scope (e.g. in case of failures)
# and are therefore not safe to be used in (alias) functions, but only in scripts.

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# Include safe Git helper functions
. "$($PSScriptRoot)/_git_common_safe.ps1"

function RunGitCommandSafely() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Git command to be executed")]
		[ValidateNotNullOrEmpty()]
		[string]$gitCommand,

		[Parameter(Mandatory=$False, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[Int]$changedFileCount = 0)
	[bool]$execStatus = RunCommand $gitCommand -silentCommandExecution
	If (-Not $execStatus) {
		If ($changedFileCount -gt 0) {
			Log Warning "Remember to run 'git stash pop' to restore $($changedFileCount) changed files"
		}

		ScriptFailure "Git command failed"
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
	RunGitCommandSafely -gitCommand "git fetch -pq --jobs=$($jobCount)"
}

function GetCurrentBranchName() {
	[OutputType([string])]
	Param()
	[string]$currentBranchName = git rev-parse --abbrev-ref HEAD
	If ([string]::IsNullOrWhiteSpace($currentBranchName)) {
		ScriptFailure "Unable to get current Git branch name"
	}
	return $currentBranchName;
}

function StashChangesAndGetChangedFileCount() {
	[OutputType([Int])]
	Param()
	[string[]]$allChangedFiles = git status -su;
	If ($allChangedFiles.Count -Eq 0 ) {
		Log Success "No files changed -> no stashing"
	} Else {
		Log Warning "Stashing $($allChangedFiles.Count) changed files"
		RunGitCommandSafely -gitCommand "git stash --include-untracked"
	}
	return $allChangedFiles.Count;
}
