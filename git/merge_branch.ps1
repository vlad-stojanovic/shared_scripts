Param(
	[Parameter(Mandatory=$False)]
	[string]$mergeSourceBranchName = $Null,

	[Parameter(Mandatory=$False)]
	[string]$commit = $Null,

	[Parameter(Mandatory=$False)]
	[switch]$rebase,
	
	[Parameter(Mandatory=$False)]
	[switch]$skipRemoteBranchInfoUpdate)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Get current git branch
$gitInitialBranch = GetCurrentBranchName

If (-Not $skipRemoteBranchInfoUpdate.IsPresent) {
	# Update list of branches from remote origin
	UpdateBranchesInfoFromRemote
}

# Stash initial changes to enable pull/merge/checkout
$gitFilesChanged = StashChangesAndGetChangedFileCount

If ([string]::IsNullOrWhiteSpace($mergeSourceBranchName)) {
	$mergeSourceBranchName = GetDefaultBranchName
} Else {
	$mergeSourceBranchName = GetExistingBranchName -branchName $mergeSourceBranchName
}

If ([string]::IsNullOrWhiteSpace($mergeSourceBranchName)) {
	ScriptFailure "Merge source branch is required!"
}

# If we aren't already on the merge source branch then switch
$pullBranchName = $gitInitialBranch
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommandSafely -gitCommand "git checkout $($mergeSourceBranchName)" -changedFileCount $gitFilesChanged
	$pullBranchName = $mergeSourceBranchName
}

If (DoesBranchExistOnRemoteOrigin -fullBranchName $pullBranchName) {
	If ([string]::IsNullOrWhiteSpace($commit)) {
		# Update the branch (pull new changes)
		RunGitCommandSafely -gitCommand "git pull -q" -changedFileCount $gitFilesChanged
	} Else {
		RunGitCommandSafely -gitCommand "git reset --hard $($commit)"
	}
} Else {
	# Branch does not exist on the remote origin - we cannot perform git pull
	LogWarning "git pull not possible for local branch [$($pullBranchName)]"
}

# If we weren't initially on merge source branch then switch back and merge
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommandSafely -gitCommand "git checkout $gitInitialBranch" -changedFileCount $gitFilesChanged
	RunGitCommandSafely -gitCommand "git merge $mergeSourceBranchName" -changedFileCount $gitFilesChanged
	If ($rebase.IsPresent -And (ConfirmAction "Rebase to $($mergeSourceBranchName) and reset/squash other committed changes visible in the PR")) {
		RunGitCommandSafely -gitCommand "git rebase origin/$($mergeSourceBranchName)" -changedFileCount $gitFilesChanged
		RunGitCommandSafely -gitCommand "git push --force" -changedFileCount $gitFilesChanged
	}
}

# Stash pop initial changes
If ($gitFilesChanged -Gt 0) {
	RunGitCommandSafely -gitCommand "git stash pop" -changedFileCount $gitFilesChanged
}

LogSuccess "Successfully updated branch [$($gitInitialBranch)] from [$($mergeSourceBranchName)]"
