Param(
	[Parameter(Mandatory=$False)]
	[switch]$skipRemoteBranchInfoUpdate)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If (-Not $skipRemoteBranchInfoUpdate.IsPresent) {
	# Update list of branches from remote origin
	UpdateBranchesInfoFromRemote
}

# List all branches & filter only the branches deleted from the remote origin
$deletedBranchRegex = "((: )|(\[))gone\]"
[string[]]$currentBranchesDeleted = git branch --verbose | Where-Object { $_ -imatch "\*.*$($deletedBranchRegex)" } | ForEach-Object { $_.Trim().Split()[1] }
If ($currentBranchesDeleted.Count -Gt 0) {
	# Switch to default branch to enable deletion of the current branch
	# which is deleted from the remote origin
	[string]$defaultBranchName = GetDefaultBranchName
	Log Warning "Switching away from current branch [$($currentBranchesDeleted[0])] which is deleted from the remote origin"
	Log Warning "NOTE: The default branch [$defaultBranchName] will not be automatically updated!`nIf needed - merge/pull manually afterwards"
	Invoke-Expression "$($PSScriptRoot)\switch_to_clean_branch.ps1 -branchName $($defaultBranchName) -skipRemoteBranchInfoUpdate -skipPullOnNewBranch"
}

[string[]]$allDeletedBranches = git branch --verbose | Where-Object { $_ -imatch $deletedBranchRegex } | ForEach-Object { $_.Trim().Split()[0] }
If ($allDeletedBranches.Count -Gt 0) {
	Log Warning "Cleaning $($allDeletedBranches.Count) deleted remote branche(s)"
	# Clean the remotely deleted branches, force to avoid asking for confirmation
	ForEach ($deletedBranch in $allDeletedBranches) {
		git branch -df $deletedBranch
	}
} Else {
	Log Success "No deleted remote branches to clean locally"
}
