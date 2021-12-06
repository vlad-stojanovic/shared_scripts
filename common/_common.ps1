function Log() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[ConsoleColor]$color)
	If (-Not($message -Is [string])) {
		$message = ($message | Out-String)
	}
	$message = "[$(Get-Date -Format 'HH:mm:ss')] $($message)"
	Write-Host $message -ForegroundColor $color
}

function LogNewLine() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$False)]
		[UInt16]$count = 1)
	For ($i = 0; $i -Lt $count; $i++) {
		Write-Host ""
	}
}

function LogInfo() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color White
}

function LogSuccess() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color Green
}

function LogWarning() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color DarkYellow
}

function LogError() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	Log -message $message -color Red
}

function ScriptExit() {
	[OutputType([System.Void])]
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
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[object]$message)
	ScriptExit -exitStatus 1 -message $message
}

function ConfirmAction() {
	[OutputType([bool])]
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

	$choice = $Host.UI.PromptForChoice("`nPlease confirm", "$($question) ?`n", ('&Yes', '&No'), $defaultAnswer)
	return ($choice -Eq 0)
}

function GetAbsolutePath() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$entityName)

	[string]$absPath = Resolve-Path $entityName -ErrorAction SilentlyContinue -ErrorVariable _rpError `
		| Select-Object -ExpandProperty Path
	if (-Not($absPath)) {
		$absPath = $_rpError[0].TargetObject
	}

	return $absPath
}

function CopyFileSafely() {
	[OutputType([System.Void])]
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
	[OutputType([System.Void])]
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
			$inputLineNumber = 0
			$newContent = Get-Content -Path "$path" `
				| ForEach-Object {
					$inputLineNumber++
					If($inputLineNumber -Eq $lineNumber) {
						# Add output additional line
						LogSuccess "$($message) @ line $($lineNumber)"
						$isTextAdded = $True
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
	[OutputType([string[]])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$searchDirectory,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$fileFilter,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$pattern,

		[Parameter(Mandatory=$False)]
		[string[]]$includePaths = $Null,

		[Parameter(Mandatory=$False)]
		[string[]]$excludePaths = $Null)

	function isSubPath() {
		[OutputType([bool])]
		Param(
			[Parameter(Mandatory=$True)]
			[bool]$allowEmptySubPath,

			[Parameter(Mandatory=$True)]
			[ValidateNotNullOrEmpty()]
			[string]$startPath,

			[Parameter(Mandatory=$True)]
			[ValidateNotNullOrEmpty()]
			[string]$fullName,

			[Parameter(Mandatory=$False)]
			[string[]]$paths = $Null)

		# Make an absolute starting path
		$startPath = Resolve-Path -Path $startPath | Select-Object -ExpandProperty Path
		If (($Null -Eq $paths) -Or (0 -Eq $paths.Count)) {
			return $allowEmptySubPath
		}

		[string[]]$absolutePaths = $paths | ForEach-Object {
			If ([System.IO.Path]::IsPathRooted($_)) {
				return $_
			} Else {
				return Join-Path -Path $startPath -ChildPath $_ -Resolve
			}
		}

		ForEach ($absolutePath in $absolutePaths) {
			If ($fullName -Eq $absolutePath) {
				# Matched a file or folder by its full name
				return $True
			}
			If ((Test-Path -Path $absolutePath -PathType Container) -And
				# Every container has to end with a path delimiter,
				# for starts-with comparison to work properly
				$fullName.StartsWith((Join-Path -Path $absolutePath -ChildPath '' -Resolve))) {
				return $True
			}
		}

		return $False
	}

	return Get-ChildItem -Path $searchDirectory -Filter $fileFilter -Recurse -ErrorAction SilentlyContinue -Force -File `
		| Where-Object { isSubPath -fullName $_.FullName -paths $includePaths -allowEmptySubPath $True -startPath $searchDirectory } `
		| Where-Object { -Not (isSubPath -fullName $_.FullName -paths $excludePaths -allowEmptySubPath $False -startPath $searchDirectory) } `
		| Select-String -Pattern $pattern | Select-Object -ExpandProperty Path `
		| Get-Unique
}

function IsFileNotEmpty() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$path)
	$children = Get-ChildItem -Path $path -Force -ErrorAction SilentlyContinue
	return ($children.Length -Gt 0)
}

function GetStopWatchDuration() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[System.Diagnostics.StopWatch]$stopWatch,

		[Parameter(Mandatory=$False)]
		[switch]$stop)
	If ($stop.IsPresent) {
		$stopWatch.Stop()
	}

	If ($stopWatch.Elapsed.TotalHours -Ge 1) {
		return $stopWatch.Elapsed.ToString("hh\:mm\:ss")
	} ElseIf ($stopWatch.Elapsed.TotalMinutes -Ge 1) {
		return $stopWatch.Elapsed.ToString("mm\:ss")
	} Else {
		return "$($stopWatch.Elapsed.TotalSeconds.ToString('F2'))s"
	}
}

function RunCommand() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$command,

		[Parameter(Mandatory=$False)]
		[switch]$useCmd,

		[Parameter(Mandatory=$False)]
		[switch]$silentCommandExecution,

		[Parameter(Mandatory=$False)]
		[switch]$getExecStatus,

		[Parameter(Mandatory=$False)]
		[switch]$ignoreExecErrors)
	If ($useCmd.IsPresent) {
		$command = "CMD /C `"$($command)`""
	}

	If ($silentCommandExecution.IsPresent) {
		$command = "$($command) | Out-Null"
	}

	LogInfo "Executing command [$($command)]"
	[bool]$execStatus = $False
	[string]$errorMessage = ""
	[System.Diagnostics.StopWatch]$stopWatch = [System.Diagnostics.StopWatch]::StartNew()
	Try {
		# Return exit status via $? variable
		$execStatus = Invoke-Expression "$($command); `$?"
	} Catch {
		$errorMessage = $_.Exception.Message
		$execStatus = $False
	}

	[string]$durationStr = GetStopWatchDuration -stopWatch $stopWatch -stop
	If ($ignoreExecErrors.IsPresent) {
		LogSuccess "Command [$($command)] executed after $($durationStr)"
	} ElseIf ($execStatus) {
		LogSuccess "Command [$($command)] successful after $($durationStr)"
	} Else {
		$failureDescription = "Command [$($command)] failed after $($durationStr)"
		If (-Not [string]::IsNullOrWhiteSpace($errorMessage)) {
			$failureDescription = "$($failureDescription) with error: $($errorMessage)"
		}

		LogError $failureDescription
	}

	If ($getExecStatus.IsPresent) {
		return $execStatus
	} Else {
		return $Null
	}
}

function GetSizeString() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[UInt64]$size,

		[Parameter(Mandatory=$False)]
		[string]$unit = "")

	[UInt64]$kilo = 1000
	[HashTable]$sizeMap = @{
		$kilo = "K"
		($kilo * $kilo) = "M"
		($kilo * $kilo * $kilo) = "G"
		($kilo * $kilo * $kilo * $kilo) = "T"
		($kilo * $kilo * $kilo * $kilo * $kilo) = "P"
	}

	[UInt64]$sizeFactor = 1
	[string]$unitPrefix = ""
	ForEach ($sizeKey in ($sizeMap.Keys | Sort-Object -Descending)) {
		If ($size -Ge $sizeKey) {
			$sizeFactor = $sizeKey
			$unitPrefix = $sizeMap[$sizeKey]
			# Break on first/largest match
			break
		}
	}

	# If the number is not an integer - format it to two decimal places
	return "$(($size / $sizeFactor).ToString('#.##'))$($unitPrefix)$($unit)"
}