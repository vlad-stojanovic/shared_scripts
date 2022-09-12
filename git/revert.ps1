Param(
	[Parameter(Mandatory=$True, HelpMessage="Commit hash to sync the local repo to")]
	[ValidateNotNullOrEmpty()]
	[string]$commit)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Stash initial changes to enable revert action w/o conflicts
[Int]$changedFileCount = StashChangesAndGetChangedFileCount

If (-Not (CheckCommitDetails -commit $commit)) {
	ScriptFailure "Cannot revert commit [$($commit)]"
}

RunGitCommand -gitCommand "revert" -parameters @($commit) -changedFileCount $changedFileCount

# Stash pop initial changes
UnstashChanges -changedFileCount $changedFileCount

Log Success "Successfully reverted commit [$($commit)] on branch [$(GetCurrentBranchName)]"
