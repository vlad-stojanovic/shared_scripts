Param(
	[Parameter(Mandatory=$False)]
	[string]$branchName = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If ([string]::IsNullOrWhiteSpace($branchName)) {
	LogWarning "Available Git branches:"
	git branch
	ScriptFailure "Branch name is required\n\t$(Split-Path -Path $PSCommandPath -Leaf) -branchName BRANCH_NAME"
}

UpdateBranchesInfoFromRemote

# Stash initial changes to enable pull/merge/checkout
$gitFilesChanged = StashChangesAndGetChangedFileCount

# Reset all commits worked on the current branch
RunGitCommandSafely -gitCommand "git reset --hard origin/master" -changedFileCount $gitFilesChanged

# Check whether the provided branch exists
$existingBranchName = GetExistingBranchName $branchName
If ([string]::IsNullOrWhiteSpace($existingBranchName)) {
	$branchName = GetBranchFullName -branchName $branchName
	
	If (ConfirmAction -question "Create new branch [$($branchName)])") {
		RunGitCommandSafely -gitCommand "git checkout -b $($branchName)" -changedFileCount $gitFilesChanged;
		LogSuccess "Successfully created new branch [$($branchName)]"
	} Else {
		LogWarning "Skipped creating new branch [$($branchName)]"
	}
} Else {
	$branchName = $existingBranchName
	LogWarning "Switching to existing branch [$($branchName)]"
	RunGitCommandSafely -gitCommand "git checkout $($branchName)" -changedFileCount $gitFilesChanged
	If (DoesBranchExistOnRemoteOrigin -branchName $branchName) {
		RunGitCommandSafely -gitCommand "git pull -q" -changedFileCount $gitFilesChanged
	} Else {
		LogWarning "Branch [$($branchName)] does not exist in remote origin. Skipping pull."
	}
	LogSuccess "Successfully switched to existing branch [$($branchName)]"
}

# Stash pop initial changes
If ($gitFilesChanged -Gt 0) {
	RunGitCommandSafely -gitCommand "git stash pop" -changedFileCount $gitFilesChanged
}
