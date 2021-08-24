Param(
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$startDir,

	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$False)]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# Fixing the issue of potentially incorrect path separators i.e. \ vs /
$startDir = Resolve-Path -Path $startDir
Push-Location -Path $startDir

[string]$absFilePath = GetAbsolutePath $filePath
If ([string]::IsNullOrWhiteSpace($absFilePath)) {
	ScriptFailure -message "File [$($filePath)] not found"
}

[string]$projectPath = $Null
[string]$folderPath = $absFilePath

Do {
	# Do not search recursively (again) through the previously searched folder
	[string[]]$excludePaths = @($folderPath)
	$folderPath = Split-Path -Path $folderPath -Parent
	If ([string]::IsNullOrWhiteSpace($folderPath)) {
		break;
	}
	LogInfo "Checking folder path [$($folderPath)]"
	$searchPattern = "\b$(Split-Path -Path $filePath -Leaf)\b"
	[string[]]$projectFiles = FindFilesContainingPattern -searchDirectory `
		$folderPath -fileFilter "*proj" -pattern $searchPattern -excludePaths $excludePaths
	If ($projectFiles.Count -Gt 1) {
		LogWarning $projectFiles
		ScriptFailure "Found $($projectFiles.Count) matching project files"
	} ElseIf ($projectFiles.Count -Eq 1) {
		$projectPath = $projectFiles[0]
		LogSuccess "`tFound closest project @ $($projectPath)"
		break
	} Else {
        LogWarning "`tMatching project not found in [$($folderPath)]"
	}

	If ($folderPath -Eq $startDir) {
		LogWarning "Searched the entire starting directory [$($startDir)]"
		break
	}
}
While ([string]::IsNullOrWhiteSpace($projectPath))

If ([string]::IsNullOrWhiteSpace($projectPath)) {
	ScriptFailure -message "Could not find closest project for file [$filePath]"
}

If (-Not $dryRun.IsPresent) {
	LogInfo "Starting project [$($projectPath)]`n"
	ScopasVS $projectPath
}

Pop-Location