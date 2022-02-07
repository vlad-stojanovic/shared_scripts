# File includes common helper functions that are guaranteed not to exit the calling scope
# and are therefore safe to be used in other functions, scripts, etc.

. (Join-Path -Path $PSScriptRoot -ChildPath "_file_common_safe.ps1")

function GetLogFilePath() {
	[OutputType([string])]
	Param()
	return (Join-Path -Path $PSScriptRoot -ChildPath "../logs/script_execution_$(Get-Date -Format 'yyyy-MM-dd')_PID-$($PID).log")
}

function PersistLogMessageToFile() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Log message value")]
		[ValidateNotNullOrEmpty()]
		[string]$message)
	[string]$logFilePath = GetLogFilePath
	CreateFileIfNotExists -filePath $logFilePath
	Add-Content -Path $logFilePath -Encoding Unicode -Value $message
}

function Log() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Type of log entry")]
		[ValidateSet("Verbose", "Info", "Success", "Warning", "Error")]
		[string]$type,

		[Parameter(Mandatory=$True, HelpMessage="Log message value")]
		[ValidateNotNullOrEmpty()]
		[object]$message,

		[Parameter(Mandatory=$False, HelpMessage="Indent level i.e. number of TABs prefixed to the message")]
		[Byte]$indentLevel = 0,

		[Parameter(Mandatory=$False, HelpMessage="Additional entries to be logged in separate new lines")]
		[string[]]$additionalEntries = @(),

		[Parameter(Mandatory=$False, HelpMessage="Optional prefix for each additional entry")]
		[AllowNull()]
		[string]$entryPrefix = "",

		[Parameter(Mandatory=$False, HelpMessage="Do not persist the message to a log file, just write to host (console)")]
		[switch]$noPersist)
	[System.Text.StringBuilder]$sbMessage = New-Object System.Text.StringBuilder
	[string]$indentUnit = "`t"
	[string]$messageIndent = "".PadLeft($indentLevel, $indentUnit)
	$sbMessage.Append($messageIndent) | Out-Null
	$sbMessage.Append("[$(Get-Date -Format 'HH:mm:ss')] ") | Out-Null
	If ($message -Is [string]) {
		$sbMessage.Append($message) | Out-Null
	} Else {
		$sbMessage.Append(($message | Out-String)) | Out-Null
	}

	If ($additionalEntries.Count -Gt 0) {
		# Move each entry to a new row and add one more indent level
		[string]$entryIndent = "`n$($messageIndent)$($indentUnit)"
		$additionalEntries | ForEach-Object {
			$sbMessage.Append("$($entryIndent)$($entryPrefix)$($_)") | Out-Null
		}
	}

	[ConsoleColor]$color = switch ($type) {
		"Verbose" { [System.ConsoleColor]::White; break }
		"Info" { [System.ConsoleColor]::Cyan; break }
		"Success" { [System.ConsoleColor]::Green; break }
		"Warning" { [System.ConsoleColor]::DarkYellow; break }
		"Error" { [System.ConsoleColor]::Red; break }
		default { [System.ConsoleColor]::White; break }
	}

	# Display formatted message in the console
	Write-Host $sbMessage.ToString() -ForegroundColor $color

	If (-Not $noPersist.IsPresent) {
		# Prepend stack trace info and persist the formatted message in the log file
		[string]$stackTraceInfo = Get-PSCallStack |
			Where-Object { $_.Command -INe "<ScriptBlock>" } |
			ForEach-Object { "$($_.Command) @ $($_.ScriptName):$($_.ScriptLineNumber)" } |
			Select-Object -Last 1
		PersistLogMessageToFile -message "$($stackTraceInfo)`n[$($type)]$($sbMessage.ToString())"
	}
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

function CheckEntryCount() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Collection of entries")]
		[AllowNull()]
		[string[]]$entries,

		[Parameter(Mandatory=$True, HelpMessage="Description for the provided entries")]
		[ValidateNotNullOrEmpty()]
		[string]$description,

		[Parameter(Mandatory=$False, HelpMessage="Expected count of entries")]
		[UInt16]$expected = 1,

		[Parameter(Mandatory=$False, HelpMessage="Use expected count as (inclusive) lower threshold")]
		[switch]$min,

		[Parameter(Mandatory=$False, HelpMessage="Use expected count as (inclusive) upper threshold")]
		[switch]$max,

		[Parameter(Mandatory=$False, HelpMessage="Location of the entries")]
		[string]$location = $Null,

		[Parameter(Mandatory=$False, HelpMessage="Indent level i.e. number of TABs prefixed to the error messages")]
		[Byte]$indentLevel = 0)
	If (($entries.Count -Eq $expected) -Or
		($min.IsPresent -And $entries.Count -Ge $expected) -Or
		($max.IsPresent -And $entries.Count -Le $expected)) {
		return $True
	}

	[string]$fullDescription = $description
	If (-Not [string]::IsNullOrWhiteSpace($location)) {
		$fullDescription = "$($fullDescription) in [$($location)]"
	}

	For ($ei = 0; $ei -Lt $entries.Count; $ei++) {
		If ([string]::IsNullOrEmpty($entries[$ei])) {
			Log -type Error -message "Invalid #$($ei + 1)/$($entries.Count) $($fullDescription)" -indentLevel $indentLevel
			return $False
		}
	}

	If ($entries.Count -Gt 0) {
		Log -type Error -message "Found $($entries.Count) $($fullDescription):" -additionalEntries $entries -entryPrefix "- " -indentLevel $indentLevel
	} Else {
		Log -type Error -message "Did not find any $($fullDescription)" -indentLevel $indentLevel
	}

	return $False
}

function ConfirmAction() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Question provided for confirmation")]
		[ValidateNotNullOrEmpty()]
		[string]$question,

		[Parameter(Mandatory=$False, HelpMessage="Should the default answer be 'Yes'")]
		[switch]$defaultYes)

	[Byte]$defaultAnswer = 1
	If ($defaultYes.IsPresent) {
		$defaultAnswer = 0
	}

	[Byte]$choice = $Host.UI.PromptForChoice("`n[$(Get-Date -Format 'HH:mm:ss')] Please confirm", "$($question) ?`n", ('&Yes', '&No'), $defaultAnswer)
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
			Log -type Success -message "Overwriting file [$copyFileName]" -indentLevel 1
		} Else {
			Log -type Warning -message "Skipping copy of [$copyFileName]" -indentLevel 1
			return
		}
	} Else {
		Log -type Success -message "Copying file [$copyFileName]"
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
						Log -type Success -message "$($message) @ line $($lineNumber)"
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
			Log -type Success -message "$($message) @ EOF"
			Add-Content -Path $path -Value $text
		}

		Log -type Success -message "$($text.Trim())" -indentLevel 1
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
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Command to be executed")]
		[ValidateNotNullOrEmpty()]
		[string]$command,

		[Parameter(Mandatory=$False, HelpMessage="Use CMD (i.e. command prompt) for command execution")]
		[switch]$useCmd,

		[Parameter(Mandatory=$False, HelpMessage="Do not show any standard-output logs, note that Host logs will be shown anyway")]
		[switch]$silentCommandExecution,

		[Parameter(Mandatory=$False, HelpMessage="Confirm command before execution, with default option 'Yes'")]
		[switch]$confirm = $Null)
	If ($useCmd.IsPresent) {
		$command = "CMD /C `"$($command)`""
	}

	If ($silentCommandExecution.IsPresent) {
		$command = "$($command) | Out-Null"
	}

	If ($confirm.IsPresent) {
		If (-Not (ConfirmAction "Execute command [$($command)]" -defaultYes)) {
			# If the action was not confirmed then fail the execution
			return $False
		}
	} Else {
		Log -type Info -message "Executing command [$($command)]"
	}

	[bool]$execStatus = $False
	[string]$errorMessage = ""
	[System.Diagnostics.StopWatch]$stopWatch = [System.Diagnostics.StopWatch]::StartNew()
	Try {
		# Return exit status via $? variable, which will the last line in the command output.
		# The command may produce multiple output lines during its execution.
		[string[]]$commandOutput = Invoke-Expression "$($command); `$?"
		If ($commandOutput.Count -Eq 0) {
			$execStatus = $False
			$errorMessage = "No command output produced (execution status is not present)"
		} Else {
			[string]$execStatusStr = $commandOutput[$commandOutput.Count - 1]
			If ((-Not [bool]::TryParse($execStatusStr, [ref]$execStatus))) {
				$execStatus = $False
				$errorMessage = "Unable to parse command output line #$($commandOutput.Count - 1) '$($execStatusStr)' into boolean execution status"
			}
		}
	} Catch {
		$errorMessage = $_.Exception.Message
		$execStatus = $False
	}

	[string]$durationStr = GetStopWatchDuration -stopWatch $stopWatch -stop
	If ($execStatus) {
		Log -type Success -message "Command [$($command)] successful after $($durationStr)"
	} Else {
		$failureDescription = "Command [$($command)] failed after $($durationStr)"
		If (-Not [string]::IsNullOrWhiteSpace($errorMessage)) {
			$failureDescription = "$($failureDescription) with error: $($errorMessage)"
		}

		Log -type Error -message $failureDescription
	}

	return $execStatus
}

function GetSizeString() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True)]
		[UInt64]$size,

		[Parameter(Mandatory=$False)]
		[string]$unit = "",

		[Parameter(Mandatory=$False)]
		[Byte]$decimalPoints = 2)

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

	# If the number is not an integer - format it to three decimal places
	[string]$integerFormat = "#."
	[string]$decimalFormat = $integerFormat.PadRight($integerFormat.Length + $decimalPoints, "#")
	return "$(($size / $sizeFactor).ToString($decimalFormat))$($unitPrefix)$($unit)"
}
