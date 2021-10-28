# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function RunGitCommandSafely() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$gitCommand,

		[Parameter(Mandatory=$False)]
		[Int]$changedFileCount = 0)
	[bool]$execStatus = RunCommand $gitCommand -silentCommandExecution -getExecStatus
	If (-Not $execStatus) {
		If ($changedFileCount -gt 0) {
			LogWarning "Remember to run 'git stash pop' to restore $($changedFileCount) changed files"
		}

		ScriptFailure "Git command failed"
	}
}

function GetDefaultBranchName() {
	# Parsing via Select-String e.g. 'origin/default' to 'default'
	[string]$defaultBranchName = git rev-parse --abbrev-ref origin/HEAD | Select-String -Pattern '[^\/]*$' | ForEach-Object { $_.Matches[0].Value }
	If ([string]::IsNullOrWhiteSpace($defaultBranchName)) {
		ScriptFailure "Could not find default branch name"
	}
	return $defaultBranchName
}

function GetBranchFullName() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$branchName)

	function getGitUserName() {
		$gitUserName = git config credential.username;
		If ([String]::IsNullOrWhiteSpace($gitUserName)) {
			return [System.Environment]::UserName
		}
		return $gitUserName
	}

	# If the branch name is already in the correct format simply return it
	If ($branchName.StartsWith("dev/") -Or ($branchName -Eq $(GetDefaultBranchName))) {
		return $branchName
	} 

	# Prefix the branch name with the username before creating it,
	# if it isn't already prefixed properly
	$gitUserName = getGitUserName;
	If ($branchName.StartsWith("$($gitUserName)/")) {
		return "dev/$($branchName)"
	} Else {
		return "dev/$($gitUserName)/$($branchName)"
	}
}

function GetExistingBranchName() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$branchName)

	[string[]]$inputBranchNames = @($branchName, $(GetBranchFullName -branchName $branchName));
	[string[]]$allBranches = $(git branch) -replace "(^(\*?)[ \t]+)|([ \t]+$)", "" | Where-Object { -Not [string]::IsNullOrWhiteSpace($_)}
	ForEach ($inputBranchName in $inputBranchNames) {
		[string[]]$matchedBranches = $allBranches | Where-Object { $inputBranchName -Eq ($_) }
		# Check whether the provided branch exists
		If ($matchedBranches.Count -Gt 1) {
			LogError "Found $($matchedBranches.Count) branches matching input [$($inputBranchName)]"
			return $Null
		} ElseIf ($matchedBranches.Count -Eq 1) {
			return $inputBranchName
		}
	}

	return $Null;
}

function GetCodeVersion() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$fullBranchName,

		[Parameter(Mandatory=$False)]
		[switch]$short,
		
		[Parameter(Mandatory=$False)]
		[switch]$remote)
	[System.Text.StringBuilder]$sbCommand = [System.Text.StringBuilder]::new()
	$sbCommand.Append("git rev-parse --verify --quiet ") | Out-Null
	If ($short.IsPresent) {
		$sbCommand.Append("--short ") | Out-Null
	}
	If ($remote.IsPresent) {
		$sbCommand.Append("remotes/origin/") | Out-Null
	}
	$sbCommand.Append($fullBranchName) | Out-Null
	[string]$codeVersion = Invoke-Expression -Command $sbCommand.ToString()
	return $codeVersion
}

function DoesBranchExistOnRemoteOrigin() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$fullBranchName)

	[string]$remoteCodeVersion = GetCodeVersion -fullBranchName $fullBranchName -remote
	return (-Not [string]::IsNullOrWhiteSpace($remoteCodeVersion))
}

function UpdateBranchesInfoFromRemote() {
	[UInt16]$jobCount = 1
	If ([System.Environment]::ProcessorCount -Ge 3) {
		# Take 2/3 of the available processors
		$jobCount = [System.Environment]::ProcessorCount * 2 / 3
	}

	LogWarning "If 'git fetch' takes a long time - best to first`n`t- clean up loose objects via 'git prune' or`n`t- optimize the local repo via 'git gc'"
	RunGitCommandSafely -gitCommand "git fetch -pq --jobs=$($jobCount)"
}

function GetCurrentBranchName() {
	[string]$currentBranchName = git rev-parse --abbrev-ref HEAD
	If ([string]::IsNullOrWhiteSpace($currentBranchName)) {
		ScriptFailure "Unable to get current Git branch name"
	}
	return $currentBranchName;
}

function StashChangesAndGetChangedFileCount() {
	[string[]]$allChangedFiles = git status -su;
	If ($allChangedFiles.Count -Eq 0 ) {
		LogSuccess "No files changed -> no stashing"
	} Else {
		LogWarning "Stashing $($allChangedFiles.Count) changed files"
		RunGitCommandSafely -gitCommand "git stash --include-untracked"
	}
	return $allChangedFiles.Count;
}
