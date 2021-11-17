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
	LogWarning "Available Git branches:"
	git branch
	ScriptFailure "Branch name is required`n`t$(Split-Path -Path $PSCommandPath -Leaf) -branchName BRANCH_NAME"
}

# Get current git branch
[string]$gitInitialBranch = GetCurrentBranchName
[string]$branchFullName = GetBranchFullName -branchName $branchName
If ($gitInitialBranch -Eq $branchName -Or $gitInitialBranch -Eq $branchFullName) {
	ScriptExit -exitStatus 0 -message "Already on branch [$($gitInitialBranch)]"
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
RunGitCommandSafely -gitCommand "git reset --hard origin/$(GetDefaultBranchName)" -changedFileCount $gitFilesChanged

If ([string]::IsNullOrWhiteSpace($existingBranchName)) {
	RunGitCommandSafely -gitCommand "git checkout -b $($branchFullName)" -changedFileCount $gitFilesChanged;
	LogSuccess "Successfully created new branch [$($branchFullName)]"
} Else {
	LogWarning "Switching to existing branch [$($existingBranchName)]"
	RunGitCommandSafely -gitCommand "git checkout $($existingBranchName)" -changedFileCount $gitFilesChanged
	If (DoesBranchExist -fullBranchName $existingBranchName -origin remote) {
		If ($skipPullOnNewBranch.IsPresent) {
			LogWarning "Skipping pull on the switched branch, please merge/pull manually afterwards"
		} Else {
			RunGitCommandSafely -gitCommand "git pull -q" -changedFileCount $gitFilesChanged
		}
	} Else {
		LogWarning "Branch [$($existingBranchName)] does not exist in remote origin. Skipping pull."
	}
	LogSuccess "Successfully switched to existing branch [$($existingBranchName)]"
}

# Stash pop initial changes
If ($gitFilesChanged -Gt 0) {
	RunGitCommandSafely -gitCommand "git stash pop" -changedFileCount $gitFilesChanged
}
