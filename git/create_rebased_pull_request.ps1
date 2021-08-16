Param(
	[Parameter(Mandatory=$False)]
	[string]$rebasedBranchName = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If ([string]::IsNullOrWhiteSpace($rebasedBranchName)) {
	$gitCurrentBranch = GetCurrentBranchName
	LogSuccess "Current Git branch [$($gitCurrentBranch)]"
	$rebasedBranchName="$($gitCurrentBranch)-rebased"
} Else {
	$rebasedBranchName = GetBranchFullName -branchName $rebasedBranchName
}

If (ConfirmAction "Rebase to new branch [$($rebasedBranchName)] and push from it") {
	RunGitCommandSafely "git checkout -b $($rebasedBranchName)"
	RunGitCommandSafely "git push -u origin $($rebasedBranchName)"
}
