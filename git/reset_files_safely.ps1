Param(
	[Parameter(Mandatory=$False)]
	[string]$entitySubPath = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Get current git branch
$gitInitialBranch = GetCurrentBranchName

[string[]]$diffFiles = git diff origin/master --name-only
If ($diffFiles.Count -Eq 0) {
	ScriptExit -exitStatus 0 -message "No diff files found on branch [$($gitInitialBranch)]"
}

LogWarning "Found $($diffFiles.Count) diff files on branch [$($gitInitialBranch)]`n"

$count=0
ForEach ($diffFile in $diffFiles) {
	$count++
	LogInfo "`nFile #$($count)/$($diffFiles.Count) @ [$($diffFile)]"
	If (-Not [string]::IsNullOrWhiteSpace($entitySubPath)) {
		If ($diffFile -inotmatch "(^|[\/])$($entitySubPath)($|[\/])") {
			LogInfo "`tnot matching path pattern [$entitySubPath]"
			continue	
		}
	}

	$fileName = Split-Path -Path $diffFile -Leaf
	If (ConfirmAction "Reset file #$($count)/$($diffFiles.Count) [$($fileName)])") {
		RunGitCommandSafely "(git checkout origin/master -- `"$($diffFile)`") -Or (git rm `"$($diffFile)`")"
		LogSuccess "`tReset file [$($fileName)]"
	} Else {
		LogInfo "\tSkipping reset of file [$($fileName)]"
	}
}
