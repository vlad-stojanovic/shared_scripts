# File includes helper file-search functions that are guaranteed not to exit the calling scope
# and are therefore safe to be used in other functions, scripts, etc.

# Include common safe helper functions
. "$($PSScriptRoot)/../common/_common_safe.ps1"

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

	[string]$rootDirectory = ""
	[string[]]$fullFilePaths = @()
	If ([System.IO.Path]::IsPathRooted($filePath)) {
		# Use the original file path, as it is absolute
		$fullFilePaths = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue
	} Else {
		# Try to prepend the start directory and get the absolute path
		$fullFilePaths = Join-Path -Path $startDir -ChildPath $filePath -Resolve -ErrorAction SilentlyContinue
		If ($fullFilePaths.Count -Gt 0) {
			$rootDirectory = $startDir
		} Else {
			$rootDirectory = "current folder"
			# Try to resolve file path relative to the current directory
			$fullFilePaths = Resolve-Path -Path $filePath -ErrorAction SilentlyContinue
		}
	}

	[string]$fileAbsPath = $Null
	If (-Not (CheckEntryCount -entries $fullFilePaths -description "files [$($filePath)]" -location $rootDirectory -max)) {
		# We found two or more paths
		return $Null
	} ElseIf ($fullFilePaths.Count -Eq 1) {
		$fileAbsPath = $fullFilePaths[0]
	} Else {
		Log Verbose "Searching for file [$($filePath)] in [$($startDir)]"
		[string[]]$filePathResults = Get-ChildItem -Path $startDir -Filter $filePath -Recurse -File -ErrorAction Stop |
			ForEach-Object { $_.FullName }
		If (-Not (CheckEntryCount -entries $filePathResults -description "files [$($filePath)]" -location $startDir -indentLevel 1)) {
			# We did not find exactly one path
			return $Null
		}

		$fileAbsPath = $filePathResults[0]
		Log Success "Found file @ [$($fileAbsPath)]" -indentLevel 1
	}

	If ([string]::IsNullOrWhiteSpace($fileAbsPath)) {
		Log Error -message "File [$($filePath)] not found in [$($startDir)]"
		return $Null
	}

	If (-Not $fileAbsPath.StartsWith($startDir)) {
		Log Error -message "Invalid start directory [$($startDir)] for file [$($fileAbsPath)]"
		return $Null
	}

	return $fileAbsPath
}

function find_project_for_file_in_start_dir() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Starting/root directory to search the file in")]
		[ValidateNotNullOrEmpty()]
		[string]$startDir,

		[Parameter(Mandatory=$True, HelpMessage="Absolute path, relative path (to `$startDir), or name, of a source/project (not a header) file")]
		[ValidateNotNullOrEmpty()]
		[string]$filePath)

	# Getting absolute paths.
	# Fixing the issue of potentially incorrect path separators i.e. \ vs /
	$startDir = Resolve-Path -Path $startDir -ErrorAction Stop
	[string]$fileAbsPath = find_absolute_path_in_start_dir -startDir $startDir -filePath $filePath
	If ([string]::IsNullOrWhiteSpace($fileAbsPath)) {
		Log Error "Could not find an absolute file path for [$($filePath)] in [$($startDir)]"
		return $Null
	}

	If ($fileAbsPath -imatch "proj$") {
		Log Info "Provided a project file [$($fileAbsPath)]"
		return $fileAbsPath
	}

	[string]$projectPath = $Null
	[string]$folderPath = Split-Path -Path $fileAbsPath -Parent
	[string]$searchFileNamePattern = [System.Text.RegularExpressions.Regex]::Escape((Split-Path -Path $fileAbsPath -Leaf))
	# We don't extend pattern for file name patterns, it is always the same e.g. ending with "*.cs"
	[string]$searchFileExtPattern = [System.Text.RegularExpressions.Regex]::Escape("*$([System.IO.Path]::GetExtension($filePath))") + "[`"']"
	[string]$excludePath = ""
	While ([string]::IsNullOrWhiteSpace($projectPath)) {
		If ([string]::IsNullOrWhiteSpace($folderPath)) {
			break;
		}

		# Either match by file name or projects that include all the files (with the appropriate extension).
		[string[]]$searchPatterns = @(
			, "\b$($searchFileNamePattern)[`"']"
			, $searchFileExtPattern
		)
		# Create a disjunction of all the sub-patterns.
		[string]$searchPattern = ($searchPatterns | ForEach-Object { "($($_))" }) -join "|"
		Log Verbose "Checking folder path [$($folderPath)]" # for search patterns:" -additionalEntries $searchPatterns
		[string[]]$projectFiles = FindFilesContainingPattern `
			-searchDirectory $folderPath -fileFilter "*proj" `
			-pattern $searchPattern -excludePaths @($excludePath)
		If (-Not (CheckEntryCount -entries $projectFiles -description "matching project files" -location $folderPath -max -indentLevel 1)) {
			# We found two or more project files
			return $Null
		} ElseIf ($projectFiles.Count -Eq 1) {
			$projectPath = $projectFiles[0]
			Log Success "Found closest project for [$($filePath)]" -additionalEntries @("@ [$($projectPath)]") -indentLevel 1
			break
		} Else {
			Log Warning "Matching project not found in [$($folderPath)]" -indentLevel 1
		}

		If ($folderPath -Eq $startDir) {
			Log Warning "Searched the entire starting directory [$($startDir)]"
			break
		}

		[string]$prevFolderName = Split-Path -Path $folderPath -Leaf
		$folderPath = Split-Path -Path $folderPath -Parent

		# Do not search recursively (again) through the previously searched folder
		$excludePath = $prevFolderName

		# Filter on the exact relative path for the file name/ext
		[string]$prevFolderNamePattern = [System.Text.RegularExpressions.Regex]::Escape($prevFolderName)
		$searchFileNamePattern = "$($prevFolderNamePattern)[\\/]$($searchFileNamePattern)"
	}

	If ([string]::IsNullOrWhiteSpace($projectPath)) {
		Log Error -message "Could not find closest project for file [$fileAbsPath]"
		return $Null
	}

	return $projectPath
}