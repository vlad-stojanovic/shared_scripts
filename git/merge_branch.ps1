Param(
	[Parameter(Mandatory=$False)]
	[string]$branchName = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Get current git branch
$gitInitialBranch = GetCurrentBranchName

# Update list of branches from remote origin
UpdateBranchesInfoFromRemote

# Stash initial changes to enable pull/merge/checkout
$gitFilesChanged = StashChangesAndGetChangedFileCount

$mergeSourceBranchName = "master"
If ((-Not [string]::IsNullOrWhiteSpace($branchName)) -And ($branchName -Ne $gitInitialBranch)) {
	$mergeSourceBranchName = GetExistingBranchName -branchName $branchName
	If ([string]::IsNullOrWhiteSpace($mergeSourceBranchName)) {
		$mergeSourceBranchName = $branchName
	}
}

# If we aren't already on the merge source branch then switch
$pullBranchName = $gitInitialBranch
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommandSafely -gitCommand "git checkout $($mergeSourceBranchName)" -changedFileCount $gitFilesChanged
	$pullBranchName = $mergeSourceBranchName
}

If (DoesBranchExistOnRemoteOrigin -branchName $pullBranchName) {
	# Update the branch (pull new changes)
	RunGitCommandSafely -gitCommand "git pull -q" -changedFileCount $gitFilesChanged
} Else {
	# Branch does not exist on the remote origin - we cannot perform git pull
	LogWarning "git pull not possible for local branch [$($pullBranchName)]"
}

# If we weren't initially on merge source branch then switch back and merge
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommandSafely -gitCommand "git checkout $gitInitialBranch" -changedFileCount $gitFilesChanged
	RunGitCommandSafely -gitCommand "git merge $mergeSourceBranchName" -changedFileCount $gitFilesChanged
	If (ConfirmAction "Rebase to $($mergeSourceBranchName) and reset/squash other committed changes visible in the PR") {
		RunGitCommandSafely -gitCommand "git rebase origin/$($mergeSourceBranchName)" -changedFileCount $gitFilesChanged
		RunGitCommandSafely -gitCommand "git push --force" -changedFileCount $gitFilesChanged
	}
}

# Stash pop initial changes
If ($gitFilesChanged -Gt 0) {
	RunGitCommandSafely -gitCommand "git stash pop" -changedFileCount $gitFilesChanged
}

LogSuccess "Successfully updated branch [$($gitInitialBranch)] from [$($mergeSourceBranchName)]"
