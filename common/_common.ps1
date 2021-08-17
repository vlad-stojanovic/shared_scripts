function Log() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[ConsoleColor]$color)
	If (-Not($message -Is [string])) {
		$message = ($message | Out-String);
	}
	$message = "[$(Get-Date -Format 'HH:mm:ss')] $($message)";
	Write-Host $message -ForegroundColor $color
}

function LogInfo() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color White
}

function LogSuccess() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color Green
}

function LogWarning() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color DarkYellow
}

function LogError() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color Red
}

function ScriptExit() {
	Param (
		[Parameter(Mandatory=$True)]
		[Int]$exitStatus,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)

	If ($exitStatus -Eq 0) {
		LogSuccess $message
	} Else {
		LogError $message
	}

	exit $exitStatus
}

function ScriptFailure() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	ScriptExit -exitStatus 1 -message $message
}

function ConfirmAction() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$question,

		[Parameter(Mandatory=$False)]
		[switch]$defaultYes)

	$defaultAnswer = 1
	If ($defaultYes.IsPresent) {
		$defaultAnswer = 0
	}
	$choice = $Host.UI.PromptForChoice("`nPlease confirm", "$($question) ?`n", ('&Yes', '&No'), $defaultAnswer);
	return ($choice -Eq 0);
}

function GetAbsolutePath() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$entityName)

	$absPath = Resolve-Path $entityName -ErrorAction SilentlyContinue -ErrorVariable _rpError `
		| Select-Object -ExpandProperty Path
	if (-Not($absPath)) {
		$absPath = $_rpError[0].TargetObject;
	}

	return $absPath
}

function CopyFileSafely() {
	Param (
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$sourceFilePath,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$destDirectory,

		[switch]$force)

	$copyFileName = Split-Path -Path $sourceFilePath -Leaf
	$destFilePath = Join-Path -Path $destDirectory -ChildPath $copyFileName
	If (Test-Path -Path $destFilePath -PathType Leaf) {
		If ($force.IsPresent -Or (ConfirmAction "Overwrite existing [$($copyFileName)]")) {
			LogSuccess "`tOverwriting file [$copyFileName]"
		} Else {
			LogWarning "`tSkipping copy of [$copyFileName]"
			return
		}
	} Else {
		LogSuccess "Copying file [$copyFileName]"
		New-Item -Path $destDirectory -ItemType Directory -Force | Out-Null
	}
	Copy-Item -Path $sourceFilePath -Destination $destFilePath -Force
}

function InsertTextIntoFile() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$text,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$path,

		[Parameter(Mandatory=$False)]
		[Int]$lineNumber)

		$fileName = Split-Path $path -Leaf
		$message = "Added to [$fileName]"
		$isTextAdded = $False
		If (($lineNumber -Gt 0) -And (Test-Path -Path $path -PathType Leaf)) {
			# Add to the target line
			$inputLineNumber = 0;
			$newContent = Get-Content -Path "$path" `
				| ForEach-Object {
					$inputLineNumber++
					If($inputLineNumber -Eq $lineNumber) {
						# Add output additional line
						LogSuccess "$($message) @ line $($lineNumber)"
						$isTextAdded = $True;
						$text
					}
					# Output the existing line to pipeline in any case
						$_
				}
				Set-Content -Path $path -Value $newContent
		}

		If (-Not $isTextAdded) {
			# Add to the EOF
			LogSuccess "$($message) @ EOF"
			Add-Content -Path $path -Value $text
		}

		LogSuccess "`t$($text.Trim())"
}

function FindFilesContainingPattern() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$searchDirectory,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$fileFilter,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$pattern)
	return Get-ChildItem -Path $searchDirectory -Filter $fileFilter -Recurse -ErrorAction SilentlyContinue -Force -File `
		| Select-String -Pattern $pattern | Select-Object -ExpandProperty Path `
		| Get-Unique
}

function IsFileNotEmpty() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$path)
	$children = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
	return ($children.Length -Gt 0)
}
