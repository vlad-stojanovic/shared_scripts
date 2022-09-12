Param(
	[Parameter(Mandatory=$False)]
	[string]$branchName = $Null,
	
	[Parameter(Mandatory=$False)]
	[switch]$skipRemoteBranchInfoUpdate,
	
	[Parameter(Mandatory=$False)]
	[switch]$skipPullOnNewBranch)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

If ([string]::IsNullOrWhiteSpace($branchName)) {
	Log Warning "Available Git branches:"
	git branch
	ScriptFailure "Branch name is required`n`t$(Split-Path -Path $PSCommandPath -Leaf) -branchName BRANCH_NAME"
}

# Get current git branch
[string]$gitInitialBranch = GetCurrentBranchName
[string]$branchFullName = GetBranchFullName -branchName $branchName
If ($gitInitialBranch -Eq $branchName -Or $gitInitialBranch -Eq $branchFullName) {
	ScriptSuccess "Already on branch [$($gitInitialBranch)]"
}

If (-Not $skipRemoteBranchInfoUpdate.IsPresent) {
	UpdateBranchesInfoFromRemote
}

# Check whether the provided branch exists
$existingBranchName = GetExistingBranchName $branchName
# Do not use the branchName variable directly anymore
Remove-Variable -Name branchName

If ([string]::IsNullOrWhiteSpace($existingBranchName)) {
	# If the branch does not exist then first check whether we want to create a new branch
	# otherwise fail immediately and perform no other preparation actions below e.g. 'git stash'
	If (-Not (ConfirmAction -question "Create new branch [$($branchFullName)])")) {
		ScriptFailure "Skipped creating new branch [$($branchFullName)]"
	}
}

# Stash initial changes to enable pull/merge/checkout
$gitFilesChanged = StashChangesAndGetChangedFileCount

# Reset all commits worked on the current branch
RunGitCommand -gitCommand "reset" -parameters @("--hard origin/$(GetDefaultBranchName)") -changedFileCount $gitFilesChanged

If ([string]::IsNullOrWhiteSpace($existingBranchName)) {
	RunGitCommand -gitCommand "checkout" -parameters @("-b $($branchFullName)") -changedFileCount $gitFilesChanged;
	Log Success "Successfully created new branch [$($branchFullName)]"
} Else {
	Log Warning "Switching to existing branch [$($existingBranchName)]"
	RunGitCommand -gitCommand "checkout" -parameters @($existingBranchName) -changedFileCount $gitFilesChanged
	If (DoesBranchExist -fullBranchName $existingBranchName -origin remote) {
		If ($skipPullOnNewBranch.IsPresent) {
			Log Warning "Skipping pull on the switched branch, please merge/pull manually afterwards"
		} Else {
			RunGitCommand -gitCommand "pull" -parameters @("-q") -changedFileCount $gitFilesChanged
		}
	} Else {
		Log Warning "Branch [$($existingBranchName)] does not exist in remote origin. Skipping pull."
	}
	Log Success "Successfully switched to existing branch [$($existingBranchName)]"
}

# Stash pop initial changes
UnstashChanges -changedFileCount $gitFilesChanged
