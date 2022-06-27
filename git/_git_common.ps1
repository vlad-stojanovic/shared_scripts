# File includes Git helper functions that may exit the calling scope (e.g. in case of failures)
# and are therefore not safe to be used in (alias) functions, but only in scripts.

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# Include safe Git helper functions
. "$($PSScriptRoot)/_git_common_safe.ps1"

function LogGitStashMessageOnFailure() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$stashedFileCount)
	[string]$stashCmd = "git stash pop"
	If ($stashedFileCount -Gt 0) {
		Log Warning "Remember to run '$($stashCmd)' to restore changes in $($stashedFileCount) files"
	} Else {
		Log Verbose "No files stashed - no restore needed via '$($stashCmd)'"
	}
}

function RunGitCommandSafely() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Git command to be executed")]
		[ValidateNotNullOrEmpty()]
		[string]$gitCommand,

		[Parameter(Mandatory=$False, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$changedFileCount = 0)
	# Return on command success.
	# Perform additional processing only on command failure.
	[bool]$execStatus = RunCommand $gitCommand -silentCommandExecution
	If ($execStatus) {
		return
	}

	# Extract the Git operation used
	[string]$operationLC = "command"
	If ($gitCommand.ToLower() -imatch "^git\s+([\w-]+)\b") {
		$operationLC = $Matches[1]

		# Process operations that might fail, but can be continued/aborted after manual intervention
		[string[]]$continuableOperationsLC = @("cherry-pick", "merge", "rebase", "revert")
		If ($continuableOperationsLC -icontains $operationLC) {
			Log Warning "Resolve all the $($operationLC) conflicts manually and then continue the $($operationLC) operation"
			If (ConfirmAction "Did you resolve all the $($operationLC) conflicts") {
				RunCommand "git $($operationLC) --continue" -silentCommandExecution | Out-Null
				# Git operation recovered after the initial failure.
				return
			} ElseIf (ConfirmAction "Abort $($operationLC) operation" -defaultYes) {
				RunCommand "git $($operationLC) --abort" -silentCommandExecution | Out-Null
			}
		}
	}

	LogGitStashMessageOnFailure -stashedFileCount $changedFileCount
	ScriptFailure "Git $($operationLC) failed"
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
	[string]$currentBranchName = GetCurrentBranchNameNoValidation
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
