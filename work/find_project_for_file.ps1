# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function find_absolute_path_in_start_dir() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Starting/root directory to search the file in")]
		[ValidateNotNullOrEmpty()]
		[string]$startDir,

		[Parameter(Mandatory=$True, HelpMessage="File absolute path, file relative path (to `$startDir), or file name")]
		[ValidateNotNullOrEmpty()]
		[string]$filePath)

	# Getting absolute paths.
	# Fixing the issue of potentially incorrect path separators i.e. \ vs /
	$startDir = Resolve-Path -Path $startDir -ErrorAction Stop

	[string]$fullFilePath = $Null
	If ([System.IO.Path]::IsPathRooted($filePath)) {
		# Use the original file path, as it is absolute
		$fullFilePath = $filePath
	} Else {
		# Try to prepend the start directory and get the absolute path
		$fullFilePath = Join-Path -Path $startDir -ChildPath $filePath
		$fullFilePath = Resolve-Path -Path $fullFilePath -ErrorAction SilentlyContinue
		If ([string]::IsNullOrWhiteSpace($fullFilePath)) {
			# Try to resolve file path relative to the current directory
			$fullFilePath = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue
		}
	}

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

	return $filePath
}

function find_project_for_file_in_start_dir() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$startDir,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$filePath)

	# Getting absolute paths.
	# Fixing the issue of potentially incorrect path separators i.e. \ vs /
	$startDir = Resolve-Path -Path $startDir -ErrorAction Stop
	$filePath = find_absolute_path_in_start_dir -startDir $startDir -filePath $filePath

	[string]$projectPath = $Null
	[string]$folderPath = $filePath

	If ($filePath -imatch "proj$") {
		LogInfo "Provided a project file [$($filePath)]"
		$projectPath = $filePath
	}

	While ([string]::IsNullOrWhiteSpace($projectPath)) {
		# Do not search recursively (again) through the previously searched folder
		[string[]]$excludePaths = @($folderPath)
		$folderPath = Split-Path -Path $folderPath -Parent
		If ([string]::IsNullOrWhiteSpace($folderPath)) {
			break;
		}

		LogInfo "Checking folder path [$($folderPath)]"
		$searchPattern = "\b$(Split-Path -Path $filePath -Leaf)\b"
		[string[]]$projectFiles = FindFilesContainingPattern `
			-searchDirectory $folderPath -fileFilter "*proj" `
			-pattern $searchPattern -excludePaths $excludePaths
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

	If ([string]::IsNullOrWhiteSpace($projectPath)) {
		ScriptFailure -message "Could not find closest project for file [$filePath]"
	}

	return $projectPath
}