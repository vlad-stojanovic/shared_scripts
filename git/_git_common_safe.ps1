# File includes Git helper functions that are guaranteed not to exit the calling scope
# and are therefore safe to be used in other functions, scripts, etc.

# Include common safe helper functions
. "$($PSScriptRoot)/../common/_common_safe.ps1"

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

function GetCurrentBranchNameNoValidation() {
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

function GetCodeVersion() {
	[OutputType([string])]
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

function GetCurrentCodeVersion() {	
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$False)]
		[switch]$short)
	[string]$currentBranchName = GetCurrentBranchNameNoValidation
	If ([string]::IsNullOrEmpty($currentBranchName)) {
		Log Error "No current Git branch found"
		return $Null
	}

	[string]$codeVersion = GetCodeVersion -fullBranchName $currentBranchName -short:$short.IsPresent
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

	Log Verbose "Repo URL for the local enlistment @ [$($url)]"
	return $url
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
	# Author is matched by parts of either alias or email so it is safer to check full email (in brackets),
	# in order to avoid false positives. 
	[string[]]$commitInfo = (git log $commit --no-decorate -n 1 --author="<$($authorEmail)>" --pretty=short) -join [System.Environment]::NewLine
	If ([string]::IsNullOrWhiteSpace($commitInfo)) {
		# Commit is not by the expected author - check does it even exist (and if so - who is the actual author)
		$commitInfo = git log $commit --no-decorate -n 1 --pretty=short
		If ([string]::IsNullOrWhiteSpace($commitInfo)) {
			Log Error "$($commitDescription) commit [$($commit)] not found"
		} Else {
			Log Warning "$($commitDescription) commit information (unexpected author email):`n$($commitInfo)"
		}

		return $False
	} 
	
	Log Success "$($commitDescription) commit information:`n$($commitInfo)"
	return $True
}

function ConfigureCurrentUserFromEnv() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$False, HelpMessage="User name (display version e.g. 'John Smith')")]
		[AllowNull()]
		[string]$displayUserName = $Null)
	function GitConfig() {
		[OutputType([System.Void])]
		Param(
			[Parameter(Mandatory=$True, HelpMessage="Config name")]
			[ValidateNotNullOrEmpty()]
			[string]$config,
	
			[Parameter(Mandatory=$True, HelpMessage="Config value")]
			[ValidateNotNullOrEmpty()]
			[string]$value)
		[string]$currentValue = git config $config
		If ([string]::IsNullOrEmpty($currentValue)) {
			Log Info "Setting git config '$($config)' to '$($currentValue)'"
			git config $config $value
		} ElseIf ($currentValue -IEq $value) {
			Log Success "Git config '$($config)' already set to '$($currentValue)'"
		} Else {
			Log Warning "Git config '$($config)' already set to '$($currentValue)', skipping override to '$($value)'"
		}
	}

	[string]$envUserName = [System.Environment]::UserName
	If ([string]::IsNullOrEmpty($displayUserName)) {
		$displayUserName = $envUserName
	}

	GitConfig -config "user.name" -value $displayUserName
	GitConfig -config "user.email" -value "$($envUserName)@microsoft.com"
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
