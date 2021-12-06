[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Output directory")]
	[ValidateNotNullOrEmpty()]
	[string]$directory,

	[Parameter(Mandatory=$False, HelpMessage="Output file path prefix")]
	[string]$filePathPrefix = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Output file extension e.g. 'csv'")]
	[string]$fileExtension = "csv",

	[Parameter(Mandatory=$False, HelpMessage="Number of lines to generate")]
	[int]$numberOfLines = 10,

	[Parameter(Mandatory=$False, HelpMessage="Item delimiter within the line e.g. ',' or ';'")]
	[string]$itemDelimiter = ',',

	[Parameter(Mandatory=$False, HelpMessage="Number of random words to be added in each line (if greater than zero)")]
	[int]$numberOfRandomWords = 1,

	[Parameter(Mandatory=$False, HelpMessage="Random word of this length will be added (if greater than zero)")]
	[UInt64]$randomWordLength = 100)

[int]$global:FileWriteCount = 0

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function AppendItem() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[System.Text.StringBuilder]$sb,

		[Parameter(Mandatory=$False)]
		[string]$item = $Null,

		[Parameter(Mandatory=$False)]
		[string]$delimiter = $Null,

		[Parameter(Mandatory=$False)]
		[string]$filePath = $Null,

		[Parameter(Mandatory=$False)]
		[int]$fileWriteThreshold = 0,

		[Parameter(Mandatory=$False)]
		[switch]$forceFileWrite)

	If (-Not [string]::IsNullOrEmpty($delimiter)) {
		[void]$sb.Append($delimiter)
	}

	If (-Not [string]::IsNullOrEmpty($item)) {
		[void]$sb.Append($item)
	}

	If (-Not [string]::IsNullOrEmpty($filePath)) {
		If ($sb.Length -Ge $fileWriteThreshold -Or $forceFileWrite.IsPresent) {
			$global:FileWriteCount++
			LogInfo "Write #$($global:FileWriteCount) of $(GetSizeString -size $sb.Length -unit 'B') characters to file [$($filePath)]"
			Add-Content -Path $filePath -Value $sb.ToString() -NoNewline -Encoding Ascii
			# Reset the string builder buffer
			$sb.Length = 0
		}
	}
}

If (-Not (Test-Path -Path $directory -PathType Container)) {
	ScriptFailure "Output directory not found @ [$($directory)]"
}

If ($numberOfLines % 2 -Ne 0) {
	ScriptFailure "Number of lines must be even"
}

[string]$randomWordSizeString = GetSizeString -size $randomWordLength -unit 'B'
[string]$filePath = Join-Path -Path $directory -ChildPath "$($filePathPrefix)lob-$($randomWordSizeString)_columns-$($numberOfRandomWords)_lines-$(GetSizeString -size $numberOfLines).$($fileExtension)"

If (Test-Path -Path $filePath -PathType Leaf) {
	ScriptFailure "File already exists @ [$($filePath)]"
}

[string]$fileDirectory = Split-Path $filePath -Parent
If (-Not (Test-Path -Path $fileDirectory -PathType Container)) {
	New-Item -Path $fileDirectory -ItemType Directory
}

[int]$kiloByte = 1000
[int]$fileWriteThreshold = $kiloByte * $kiloByte
[UInt64]$estimatedLineLength = $kiloByte + $numberOfRandomWords * $randomWordLength
[System.Text.StringBuilder]$bufferSb = [System.Text.StringBuilder]::new($fileWriteThreshold * 2)

[int]$logLineCadence = 1
# Ensure at most 100 logs
If ($estimatedLineLength -Lt [UInt64]$fileWriteThreshold) {
	While ($logLineCadence * 100 -Lt $numberOfLines) {
		$logLineCadence *= 10
	}
}

# Add header line
AppendItem -sb $bufferSb -item "id"
AppendItem -sb $bufferSb -item "code" -delimiter $itemDelimiter
For ($randomWordCounter = 1; $randomWordCounter -Le $numberOfRandomWords; $randomWordCounter++) {
	AppendItem -sb $bufferSb -item "word_$($randomWordSizeString)_$($randomWordCounter)" -delimiter $itemDelimiter
}

AppendItem -sb $bufferSb -item ([System.Environment]::NewLine)

If (-Not [string]::IsNullOrWhiteSpace($filePathPrefix)) {
	[string]$fileNamePrefix = Split-Path -Path $filePathPrefix -Leaf
}

# Generate and add lines
For ($lineNumber = 1; $lineNumber -Le $numberOfLines; $lineNumber++) {
	If ((($lineNumber - 1) % $logLineCadence) -Eq 0) {
		[string]$logLineInfo = "Generating line #$($lineNumber)/$($numberOfLines)"
		If ($logLineCadence -Gt 1) {
			$logLineInfo = "$($logLineInfo) (cadence $($logLineCadence))"
		}
		If ($numberOfRandomWords -Gt 0 -And $randomWordLength -Gt 0) {
			$logLineInfo = "$($logLineInfo) with $($numberOfRandomWords) random word(s) of length $($randomWordSizeString)"
		} Else {
			$logLineInfo = "$($logLineInfo) without any random words"
		}
		LogInfo $logLineInfo
	}

	# Add ID as the first item, w/o delimiter
	AppendItem -sb $bufferSb -item $lineNumber.ToString()

	# Add code as the second item, invalid in every second line.
	If ($lineNumber % 2 -Eq 0) {
		AppendItem -sb $bufferSb -item "NaN" -delimiter $itemDelimiter
	} Else {
		AppendItem -sb $bufferSb -item $lineNumber.ToString() -delimiter $itemDelimiter
	}

	For ($currentWord = 1; $currentWord -Le $numberOfRandomWords; $currentWord++) {
		# Add delimiter before creating the next random word
		AppendItem -sb $bufferSb -delimiter $itemDelimiter
		[string]$wordBlock = "row $($lineNumber) - word 1KB - number $($currentWord) of $($numberOfRandomWords) - - - "
		If (-Not [string]::IsNullOrWhiteSpace($fileNamePrefix)) {
			$wordBlock = "prefix $($fileNamePrefix) - $($wordBlock)"
		}

		[UInt64]$currentWordLength = 0
		While ($currentWordLength -Lt $randomWordLength) {
			[int]$letterLimit = [Math]::Min($randomWordLength - $currentWordLength, $wordBlock.Length)
			$currentWordLength += $letterLimit
			If ($letterLimit -Lt $wordBlock.Length) {
				AppendItem -filePath $filePath -fileWriteThreshold $fileWriteThreshold -sb $bufferSb -item $wordBlock.Substring(0, $letterLimit)
			} Else {
				AppendItem -filePath $filePath -fileWriteThreshold $fileWriteThreshold -sb $bufferSb -item $wordBlock
			}
		}
	}

	AppendItem -sb $bufferSb -item ([System.Environment]::NewLine)
}

# Force file write (as the threshold is 0) at the end,
# w/ the remaining string builder value, w/o appending any more items
AppendItem -filePath $filePath -fileWriteThreshold 0 -sb $bufferSb

& "$($PSScriptRoot)\check_alternating_lines.ps1" `
	-directory $directory `
	-expectedLobLength $randomWordLength `
	-expectedLobCount $numberOfRandomWords `
	-expectedLineCount $numberOfLines `
	-filePathPrefix $filePathPrefix `
	-fileExtension $fileExtension
[bool]$areFileContentsValid = $?
If ($areFileContentsValid) {
	LogSuccess "Result file @ [$($filePath)]"
} Else {
	ScriptFailure "Result file has invalid contents @ [$($filePath)]"
}