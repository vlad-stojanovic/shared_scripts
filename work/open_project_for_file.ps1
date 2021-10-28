Param(
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$startDir,

	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$False)]
	[string]$startProjectCmd = "start",

	[Parameter(Mandatory=$False)]
	[string[]]$parentProjects = @(),

	[Parameter(Mandatory=$False)]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

# Getting absolute paths.
# Fixing the issue of potentially incorrect path separators i.e. \ vs /
$startDir = Resolve-Path -Path $startDir -ErrorAction Stop

[string]$fullFilePath = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue
If ([string]::IsNullOrWhiteSpace($fullFilePath)) {
	LogInfo "Searching for file [$($filePath)] in [$($startDir)]"
	[string[]]$filePathResults = Get-ChildItem -Path $startDir -Filter $filePath -Recurse -File -ErrorAction Stop |
		ForEach-Object { $_.FullName }
	If ($filePathResults.Count -Eq 0) {
		ScriptFailure -message "File [$($filePath)] not found in [$($startDir)]"
	} ElseIf ($filePathResults.Count -Gt 1) {
		LogWarning ($filePathResults -join "`n")
		ScriptFailure "Found $($filePathResults.Count) files in [$($startDir)]"
	}

	$filePath = $filePathResults[0]
	LogSuccess "Found file @ [$($filePath)]"
} Else {
	$filePath = $fullFilePath
}

If ([string]::IsNullOrWhiteSpace($filePath)) {
	ScriptFailure -message "File [$($filePath)] not found"
}

If (-Not $filePath.StartsWith($startDir)) {
	ScriptFailure -message "Invalid start directory [$($startDir)] for file [$($filePath)]"
}

Push-Location -Path $startDir

[string]$projectPath = $Null
[string]$folderPath = $filePath

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

ForEach ($parentProject in $parentProjects) {
	[string]$projectName = Split-Path -Path $projectPath -Leaf
	[string]$parentProjectPath = GetAbsolutePath $parentProject
	[string]$parentProjectName = [System.IO.Path]::GetFileNameWithoutExtension($parentProjectPath)
	If ($parentProjectPath -Ieq $projectPath) {
		LogInfo "Parent project [$($parentProjectName)] is @ [$($projectPath)]"
	} ElseIf (Select-String -Path $parentProjectPath -Pattern $projectName -SimpleMatch -Quiet) {
		LogInfo "Parent project [$($parentProjectName)] contains [$($projectName)]`n`t@ [$($parentProjectPath)]"
	}
}

If (-Not $dryRun.IsPresent) {
	[string]$command = "$($startProjectCmd) `"$($projectPath)`""
	LogInfo "Starting project`n`t$($command)`n"
	Invoke-Expression -Command $command
}

Pop-Location