Param(
	[Parameter(Mandatory=$True, HelpMessage="Commit hash to sync the local repo to")]
	[ValidateNotNullOrEmpty()]
	[string]$commit,

	[Parameter(Mandatory=$False, HelpMessage="Whether we should skip update of remote branches i.e. 'git fetch'")]
	[switch]$skipRemoteBranchInfoUpdate)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If (-Not $skipRemoteBranchInfoUpdate.IsPresent) {
	# Update list of branches from remote origin
	UpdateBranchesInfoFromRemote
}

# Stash initial changes to enable cherry-pick action w/o conflicts
[Int]$changedFileCount = StashChangesAndGetChangedFileCount

If (-Not (CheckCommitDetails -commit $commit)) {
	ScriptFailure "Could not cherry-pick commit [$($commit)]"
}

RunGitCommand -gitCommand "cherry-pick" -parameters @($commit) -changedFileCount $gitFilesChanged

# Stash pop initial changes
UnstashChanges -changedFileCount $changedFileCount

Log Success "Successfully applied commit [$($commit)] on branch [$(GetCurrentBranchName)]"
