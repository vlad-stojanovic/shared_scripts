Param(
	[Parameter(Mandatory=$False, HelpMessage="Merge source branch name. If not present then it defaults to the default branch e.g. 'master' or 'main'")]
	[string]$mergeSourceBranchName = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Commit hash to sync the local repo to")]
	[string]$commit = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Whether we should attempt to rebase the current branch")]
	[switch]$rebase,
	
	[Parameter(Mandatory=$False, HelpMessage="Whether we should skip update of remote branches i.e. 'git fetch'")]
	[switch]$skipRemoteBranchInfoUpdate,
	
	[Parameter(Mandatory=$False, HelpMessage="Whether we should push the changes to remote origin after the merge completes successfully")]
	[switch]$push)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Get current git branch
$gitInitialBranch = GetCurrentBranchName
Log Verbose "Currently on branch [$($gitInitialBranch)]"

If (-Not $skipRemoteBranchInfoUpdate.IsPresent) {
	# Update list of branches from remote origin
	UpdateBranchesInfoFromRemote
}

If ([string]::IsNullOrWhiteSpace($mergeSourceBranchName)) {
	$mergeSourceBranchName = GetDefaultBranchName
} Else {
	$mergeSourceBranchName = GetExistingBranchName -branchName $mergeSourceBranchName
}

If ([string]::IsNullOrWhiteSpace($mergeSourceBranchName)) {
	ScriptFailure "Merge source branch is required!"
}

# Check for remote code version only if we are merging from the current branch,
# otherwise the commit IDs will not match (current vs merge-source branch).
If ($gitInitialBranch -Eq $mergeSourceBranchName) {
	[string]$currentCodeVersionFull = GetCodeVersion -fullBranchName $mergeSourceBranchName
	If (-Not [string]::IsNullOrWhiteSpace($commit)) {
		# If a target commit is provided then check both short and full current code versions.
		[string]$currentCodeVersionShort = GetCodeVersion -fullBranchName $mergeSourceBranchName -short
		If ($currentCodeVersionFull -IEq $commit -Or $currentCodeVersionShort -IEq $commit) {
			ScriptSuccess "Branch [$($mergeSourceBranchName)] is already on code version $($commit)"
		}
	} Else {
		# If no commit is provided then check the latest version.
		[string]$remoteCodeVersionFull = GetCodeVersion -fullBranchName $mergeSourceBranchName -remote
		If ($currentCodeVersionFull -IEq $remoteCodeVersionFull) {
			ScriptSuccess "Branch [$($mergeSourceBranchName)] is already on the latest code version $($currentCodeVersionFull)"
		}
	}
}

# Stash initial changes to enable pull/merge/checkout
[Int]$gitFilesChanged = StashChangesAndGetChangedFileCount

# If we aren't already on the merge source branch then switch
$pullBranchName = $gitInitialBranch
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommand -gitCommand "checkout" -parameters @($mergeSourceBranchName) -changedFileCount $gitFilesChanged
	$pullBranchName = $mergeSourceBranchName
}

If (DoesBranchExist -fullBranchName $pullBranchName -origin remote) {
	If ([string]::IsNullOrWhiteSpace($commit)) {
		# Update the branch (pull new changes)
		RunGitCommand -gitCommand "pull" -parameters @("-q") -changedFileCount $gitFilesChanged
	} Else {
		RunGitCommand -gitCommand "reset" -parameters @("--hard $($commit)")
	}
} Else {
	# Branch does not exist on the remote origin - we cannot perform git pull
	Log Warning "git pull not possible for local branch [$($pullBranchName)]"
}

# If we weren't initially on merge source branch then switch back and merge
If ($gitInitialBranch -Ne $mergeSourceBranchName) {
	RunGitCommand -gitCommand "checkout" -parameters @($gitInitialBranch) -changedFileCount $gitFilesChanged
	RunGitCommand -gitCommand "merge" -parameters @($mergeSourceBranchName) -changedFileCount $gitFilesChanged

	If ($rebase.IsPresent -And (ConfirmAction "Rebase to $($mergeSourceBranchName) and reset/squash other committed changes visible in the PR")) {
		RunGitCommand -gitCommand "rebase" -parameters @("origin/$($mergeSourceBranchName)") -changedFileCount $gitFilesChanged
		RunGitCommand -gitCommand "push" -parameters @("--force") -changedFileCount $gitFilesChanged
	}
}

# Stash pop initial changes
UnstashChanges -changedFileCount $gitFilesChanged

Log Success "Successfully updated branch [$($gitInitialBranch)] ($(GetCodeVersion -fullBranchName $gitInitialBranch -short)) from [$($mergeSourceBranchName)]"

If ($push.IsPresent) {
	PushBranchToOrigin -fullBranchName $gitInitialBranch -confirm
}