# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Update list of branches from remote origin
UpdateBranchesInfoFromRemote

# List all branches & filter only the branches deleted from the remote origin
$deletedBranchRegex = "((: )|(\[))gone\]"
[string[]]$currentBranchesDeleted = git branch --verbose | Where-Object { $_ -imatch "\*.*$($deletedBranchRegex)" } | ForEach-Object { $_.Trim().Split()[1] }
If ($currentBranchesDeleted.Count -Gt 0) {
	# Switch to default branch to enable deletion of the current branch
	# which is deleted from the remote origin
	LogWarning "Switching away from current branch [$($currentBranchesDeleted[0])] which is deleted from the remote origin"
	RunGitCommandSafely "git checkout $(GetDefaultBranchName)"
}

[string[]]$allDeletedBranches = git branch --verbose | Where-Object { $_ -imatch $deletedBranchRegex } | ForEach-Object { $_.Trim().Split()[0] }
If ($allDeletedBranches.Count -Gt 0) {
	LogWarning "Cleaning $($allDeletedBranches.Count) deleted remote branche(s)"
	# Clean the remotely deleted branches, force to avoid asking for confirmation
	ForEach ($deletedBranch in $allDeletedBranches) {
		git branch -df $deletedBranch
	}
} Else {
	LogSuccess "No deleted remote branches to clean locally"
}
