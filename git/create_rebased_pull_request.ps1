Param(
	[Parameter(Mandatory=$False, "Rebased branch name, in full or short format. If not provided the current branch name will be used as base (and slightly modified).")]
	[string]$rebasedBranchName = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If ([string]::IsNullOrWhiteSpace($rebasedBranchName)) {
	$gitCurrentBranch = GetCurrentBranchName
	Log Success "Current Git branch [$($gitCurrentBranch)]"
	$rebasedBranchName="$($gitCurrentBranch)-rebased"
} Else {
	$rebasedBranchName = GetBranchFullName -branchName $rebasedBranchName
}

If (-Not (RunCommand "git checkout -b $($rebasedBranchName)" -confirm)) {
	return
}

# The branch is newly created above, it does not exist remotely.
PushBranchToOrigin -fullBranchName $rebasedBranchName -noRemoteBranch
