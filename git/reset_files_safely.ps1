Param(
	[Parameter(Mandatory=$False)]
	[string]$entitySubPath = $Null)

# Include git helper functions
. "$($PSScriptRoot)/_git_common.ps1"

# Get current git branch
$gitInitialBranch = GetCurrentBranchName

$defaultBranchName = GetDefaultBranchName

[string[]]$diffFiles = git diff origin/$defaultBranchName --name-only
If ($diffFiles.Count -Eq 0) {
	ScriptSuccess "No diff files found on branch [$($gitInitialBranch)]"
}

Log Warning "Found $($diffFiles.Count) diff files on branch [$($gitInitialBranch)]"
LogNewLine

$count=0
ForEach ($diffFile in $diffFiles) {
	$count++
	LogNewLine
	Log Info "File #$($count)/$($diffFiles.Count) @ [$($diffFile)]"
	If (-Not [string]::IsNullOrWhiteSpace($entitySubPath)) {
		If ($diffFile -inotmatch "(^|[\/])$($entitySubPath)($|[\/])") {
			Log Verbose "not matching path pattern [$entitySubPath]" -indentLevel 1
			continue	
		}
	}

	$fileName = Split-Path -Path $diffFile -Leaf
	If (ConfirmAction "Reset file #$($count)/$($diffFiles.Count) [$($fileName)])") {
		RunGitCommandSafely "(git checkout origin/$($defaultBranchName) -- `"$($diffFile)`") -Or (git rm `"$($diffFile)`")"
		Log Success "Reset file [$($fileName)]" -indentLevel 1
	} Else {
		Log Verbose "Skipping reset of file [$($fileName)]" -indentLevel 1
	}
}
