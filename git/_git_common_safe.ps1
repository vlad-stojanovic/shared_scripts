# File includes Git helper functions that are guaranteed not to exit the calling scope
# and are therefore safe to be used in other functions, scripts, etc.

# Include common safe helper functions
. "$($PSScriptRoot)/../common/_common_safe.ps1"

function LogGitStashMessageOnFailure() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$stashedFileCount)
	[string]$stashCmd = "git stash pop"
	If ($stashedFileCount -Gt 0) {
		Log Warning "Remember to run '$($stashCmd)' to restore changes in $($stashedFileCount) files"
	} Else {
		Log Verbose "No files stashed - no restore needed via '$($stashCmd)'"
	}
}

function RunGitCommandSafely() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Git command to be executed")]
		[ValidateNotNullOrEmpty()]
		[string]$gitCommand,

		[Parameter(Mandatory=$False, HelpMessage="Git command parameters")]
		[AllowNull()]
		[string[]]$parameters = $Null,

		[Parameter(Mandatory=$False, HelpMessage="Number of changed files that are stashed, and should be manually popped in case of command failure")]
		[UInt16]$changedFileCount = 0)
	If (-Not ($gitCommand -imatch '^([\w-]+)$')) {
		Log Error "Unsupported git command '$($gitCommand)'. It should be a single word, without spaces"
		return $False
	}

	If ($gitCommand -imatch "^git\b") {
		Log Error "Do not use 'git' prefix, it will be automatically prepended."
		return $False
	}

	# Return on command success.
	# Perform additional processing only on command failure.
	[bool]$execStatus = RunCommand "git $($gitCommand) $($parameters -join ' ')" -silentCommandExecution
	If ($execStatus) {
		return $True
	}

	# Process operations that might fail, but can be continued/aborted after manual intervention
	[string[]]$continuableOperationsLC = @("cherry-pick", "merge", "rebase", "revert")
	If ($continuableOperationsLC -icontains $gitCommand) {
		Log Warning "Resolve all the $($gitCommand) conflicts manually and then continue the $($gitCommand) operation"
		If (ConfirmAction "Did you resolve all the $($gitCommand) conflicts") {
			RunCommand "git $($gitCommand) --continue" -silentCommandExecution | Out-Null
			# Git operation recovered after the initial failure.
			return $True
		} ElseIf (ConfirmAction "Abort $($gitCommand) operation" -defaultYes) {
			RunCommand "git $($gitCommand) --abort" -silentCommandExecution | Out-Null
		}
	}

	LogGitStashMessageOnFailure -stashedFileCount $changedFileCount
	return $False
}

function UpdateBranchesInfoFromRemoteSafely() {
	[OutputType([bool])]
	Param()
	[UInt16]$jobCount = 1
	If ([System.Environment]::ProcessorCount -Ge 3) {
		# Take 2/3 of the available processors
		$jobCount = [System.Environment]::ProcessorCount * 2 / 3
	}

	Log Warning "If 'git fetch' takes a long time - best to first" -additionalEntries @(
		"clean up loose objects via 'git prune' or",
		"optimize the local repo via 'git gc'") -entryPrefix "- "
	return (RunGitCommandSafely -gitCommand "fetch" -parameters @("-pq", "--jobs=$($jobCount)"))
}

function GetDefaultBranchName() {
	[OutputType([string])]
	Param()
	# Parsing via Select-String e.g. 'origin/default' to 'default'
	[string]$defaultBranchName = git rev-parse --abbrev-ref origin/HEAD | Select-String -Pattern '[^\/]*$' | ForEach-Object { $_.Matches[0].Value }
	If ([string]::IsNullOrWhiteSpace($defaultBranchName)) {
		Log Error "Could not find default branch name"
		return $Null
	}

	return $defaultBranchName
}

function GetCurrentBranchNameSafely() {
	[OutputType([string])]
	Param()	
	return (git rev-parse --abbrev-ref HEAD)
}

function GetBranchFullName() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Branch name, either full or short format")]
		[ValidateNotNullOrEmpty()]
		[string]$branchName)

	function getGitUserName() {
		[OutputType([string])]
		Param()
		$gitUserName = git config credential.username;
		If ([String]::IsNullOrWhiteSpace($gitUserName)) {
			return [System.Environment]::UserName
		}
		return $gitUserName
	}

	# If the branch name is already in the correct format then simply return it e.g.
	# - dev/ALIAS/BRANCH_NAME e.g. dev/vstojanovic/my-branch
	# - rel/TRAIN_TYPE/TRAIN_NAME e.g. rel/st/ST10.2
	# - DEFAULT_BRANCH_NAME e.g. master
	If ($branchName.StartsWith("dev/") -Or $branchName.StartsWith("rel/") -Or ($branchName -Eq $(GetDefaultBranchName))) {
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

function CheckCommitDetails() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Commit to check")]
		[ValidateNotNullOrEmpty()]
		[string]$commit,

		[Parameter(Mandatory=$False, HelpMessage="Format of the expected commit details")]
		[ValidateNotNullOrEmpty()]
		# See https://git-scm.com/docs/git-show#_pretty_formats for format descriptions
		[string]$prettyFormat = "fuller")
	[string[]]$commitDetails = git show -s --pretty=$prettyFormat $commit
	If ($Null -Eq $commitDetails -Or $commitDetails.Count -Eq 0) {
		Log Warning "Could not find commit [$($commit)] details." -additionalEntries @("Did you perform 'git fetch/pull/merge' to get the latest information?")
		return $False
	}

	Log Verbose "Commit [$($commit)] details" -additionalEntries $commitDetails
	return $True
}

function GetCodeVersion() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Full branch name")]
		[ValidateNotNullOrEmpty()]
		[string]$fullBranchName,

		[Parameter(Mandatory=$False, HelpMessage="Get short commit hash")]
		[switch]$short,

		[Parameter(Mandatory=$False, HelpMessage="Check code version for the remote branch, instead of the local one")]
		[switch]$remote,

		[Parameter(Mandatory=$False, HelpMessage="Show commit details e.g. commit author/timestamp")]
		[switch]$details)
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

	If ($details.IsPresent) {
		CheckCommitDetails -commit $codeVersion | Out-Null
	}

	return $codeVersion
}

function GetCurrentCodeVersion() {	
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$False, HelpMessage="Get short commit hash")]
		[switch]$short,

		[Parameter(Mandatory=$False, HelpMessage="Show commit details e.g. commit author/timestamp")]
		[switch]$details)
	[string]$currentBranchName = GetCurrentBranchNameSafely
	If ([string]::IsNullOrEmpty($currentBranchName)) {
		Log Error "No current Git branch found"
		return $Null
	}

	[string]$codeVersion = GetCodeVersion -fullBranchName $currentBranchName -short:$short.IsPresent -details:$details.IsPresent
	Log Info "Current branch [$($currentBranchName)] is on code version [$($codeVersion)]"
	return $codeVersion
}

function DoesBranchExist() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$fullBranchName,
		
		[Parameter(Mandatory=$True)]
		[ValidateSet("local", "remote")]
		[string]$origin)
	[string]$codeVersion = GetCodeVersion -fullBranchName $fullBranchName -remote:($origin -Eq "remote")
	return (-Not [string]::IsNullOrWhiteSpace($codeVersion))
}

function GetExistingBranchName() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$branchName)
	[string[]]$inputBranchNames = @($branchName, $(GetBranchFullName -branchName $branchName));
	ForEach ($inputBranchName in $inputBranchNames) {
		# Check whether the provided branch exists locally or remotely
		If ((DoesBranchExist -fullBranchName $inputBranchName -origin local) -Or
			(DoesBranchExist -fullBranchName $inputBranchName -origin remote)) {
			return $inputBranchName
		}
	}

	return $Null
}

function PushBranchToOrigin() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Full branch name to push to origin")]
		[ValidateNotNullOrEmpty()]
		[string]$fullBranchName,

		[Parameter(Mandatory=$False, HelpMessage="Confirm push action before execution")]
		[switch]$confirm,

		[Parameter(Mandatory=$False, HelpMessage="Whether the branch does not exist remotely")]
		[switch]$noRemoteBranch)
	[string]$gitCmd = "git push"
	If ($noRemoteBranch.IsPresent -Or (-Not (DoesBranchExist -fullBranchName $fullBranchName -origin "remote"))) {
		# If the branch does not exist remotely then create it
		$gitCmd = "$($gitCmd) -u origin $($fullBranchName)"
	}

	# Ignore return value for RunCommand
	RunCommand $gitCmd -confirm:$confirm.IsPresent | Out-Null
}

function GetCurrentRepositoryUrl() {
	[OutputType([string])]
	Param()
	[string]$url = git config --get remote.origin.url
	If ([string]::IsNullOrWhiteSpace($url)) {
		Log Error "Cound not find repo URL for the local enlistment"
		return $Null
	}

	return $url
}

function GetCurrentEnlistmentRoot() {
	[OutputType([string])]
	Param()
	[string]$path = git rev-parse --show-toplevel
	If ([string]::IsNullOrWhiteSpace($path)) {
		Log Error "Cound not find root path for the local enlistment"
		return $Null
	}

	return $path
}

function IsCommitByAuthor() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Commit to check")]
		[ValidateNotNullOrEmpty()]
		[string]$commit,

		[Parameter(Mandatory=$True, HelpMessage="Commit description, used in logs")]
		[ValidateNotNullOrEmpty()]
		[string]$commitDescription,

		[Parameter(Mandatory=$True, HelpMessage="Expected author email for the provided commit")]
		[ValidateNotNullOrEmpty()]
		[string]$authorEmail)
	[string]$actualCommitAuthor = git log $commit --no-decorate --pretty=format:'%ae' -n 1
	If ([string]::IsNullOrWhiteSpace($actualCommitAuthor)) {
		Log Error "$($commitDescription) commit [$($commit)] author not found"
		return $False
	}

	[string]$commitInfo = (git log $commit --no-decorate -n 1 --pretty=short) -join [System.Environment]::NewLine
	If ([string]::IsNullOrWhiteSpace($commitInfo)) {
		Log Error "$($commitDescription) commit [$($commit)] not found"
		return $False
	}

	If ($actualCommitAuthor -INe $authorEmail) {
		Log Warning "$($commitDescription) commit information (unexpected author email):" -additionalEntries @($commitInfo)
		return $False
	}
	
	Log Success "$($commitDescription) commit information:" -additionalEntries @($commitInfo)
	return $True
}

function ConfigureCurrentUserFromEnv() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$False, HelpMessage="User name (display version e.g. 'John Smith')")]
		[AllowNull()]
		[string]$displayUserName = $Null,
	
		[Parameter(Mandatory=$False, HelpMessage="Force value update")]
		[switch]$force)
	function GitConfig() {
		[OutputType([System.Void])]
		Param(
			[Parameter(Mandatory=$True, HelpMessage="Config name")]
			[ValidateNotNullOrEmpty()]
			[string]$config,
	
			[Parameter(Mandatory=$True, HelpMessage="Config value")]
			[ValidateNotNullOrEmpty()]
			[string]$value,
	
			[Parameter(Mandatory=$False, HelpMessage="Force value update")]
			[switch]$force)
		[string]$currentValue = git config $config
		If ([string]::IsNullOrEmpty($currentValue)) {
			Log Info "Setting git config '$($config)' to '$($value)'"
			git config $config $value
		} ElseIf ($currentValue -IEq $value) {
			Log Success "Git config '$($config)' already set to '$($currentValue)'"
			return
		} ElseIf ($force.IsPresent) {
			Log Warning "Git config '$($config)' override from '$($currentValue)' to '$($value)'"
		} Else {
			Log Warning "Git config '$($config)' already set to '$($currentValue)', skipping override to '$($value)'"
		}
	}

	[string]$envUserName = [System.Environment]::UserName
	If ([string]::IsNullOrEmpty($displayUserName)) {
		# Try to read logged on display name from the registry
		$displayUserName = Get-ItemPropertyValue "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI" -ErrorAction Ignore -Name LastLoggedOnDisplayName
		# Fallback to user name (alias) from the environment
		If ([string]::IsNullOrEmpty($displayUserName)) {
			$displayUserName = $envUserName
		}
	}

	GitConfig -config "user.name" -value $displayUserName -force:$force.IsPresent
	GitConfig -config "user.email" -value "$($envUserName)@microsoft.com" -force:$force.IsPresent
}

function IsCommitByCurrentUser() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Commit to check")]
		[ValidateNotNullOrEmpty()]
		[string]$commit,

		[Parameter(Mandatory=$True, HelpMessage="Commit description, used in logs")]
		[ValidateNotNullOrEmpty()]
		[string]$commitDescription)
	[string]$currentUserEmail = git config --get user.email
	If ([string]::IsNullOrWhiteSpace($currentUserEmail)) {
		Log Error "Current user email not configured"
		return $False
	}

	return IsCommitByAuthor -commit $commit -commitDescription $commitDescription -authorEmail $currentUserEmail
}
