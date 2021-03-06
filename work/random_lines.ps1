[CmdletBinding()]
Param(
	[Parameter(Mandatory=$False, HelpMessage="Output file path prefix")]
	[string]$filePathPrefix = "temp_",

	[Parameter(Mandatory=$False, HelpMessage="Output file extension e.g. 'csv'")]
	[string]$fileExtension = "csv",

	[Parameter(Mandatory=$False, HelpMessage="Number of lines to generate")]
	[int]$numberOfLines = 5,

	[Parameter(Mandatory=$False, HelpMessage="Item delimiter within the line e.g. ',' or ';'")]
	[string]$itemDelimiter = ',',

	[Parameter(Mandatory=$False, HelpMessage="Number of random words to be added in each line (if greater than zero)")]
	[int]$numberOfRandomWords = 1,

	[Parameter(Mandatory=$False, HelpMessage="Random word of this length will be added (if greater than zero)")]
	[int]$randomWordLength = 100)

[int]$global:KB = 1000
[int]$global:MB = $global:KB * $global:KB
[int]$global:GB = $global:KB * $global:MB

[int]$global:FileWriteCount = 0

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function AppendItem() {
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
			Log Verbose "Write #$($global:FileWriteCount) of $(GetSizeString -size $sb.Length -unit 'B') characters to file [$($filePath)]"
			Add-Content -Path $filePath -Value $sb.ToString() -NoNewline -Encoding Ascii
			# Reset the string builder buffer
			$sb.Length = 0
		}
	}
}

[char[]]$alphaLetters = @(
	'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H', 'I', 'J', 'K', 'L', 'M', 'N', 'O', 'P', 'Q', 'R', 'S', 'T', 'U', 'V', 'W', 'X', 'Y', 'Z',
	'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z')
[char[]]$alphaNumLetters = $alphaLetters + @('1', '2', '3', '4', '5', '6', '7', '8', '9', '0')
[string]$numberLogFormat = "N0"
[UInt16]$decimalPoints = 3

[string]$randomWordSizeString = GetSizeString -size $randomWordLength -unit 'B' -decimalPoints $decimalPoints
[string]$linesString = GetSizeString -size $numberOfLines -unit '' -decimalPoints $decimalPoints
[string]$filePath = "$($filePathPrefix)lob-$($randomWordSizeString)_columns-$($numberOfRandomWords)_lines-$($linesString).$($fileExtension)"

If (Test-Path -Path $filePath) {
	Log Info "Removing existing file [$($filePath)]"
	Remove-Item -Path $filePath
}

CreateFileIfNotExists $filePath

[int]$fileWriteThreshold = $global:MB
[int]$estimatedLineLength = $global:KB + $numberOfRandomWords * $randomWordLength
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

# Generate and add lines
For ($lineNumber = 1; $lineNumber -Le $numberOfLines; $lineNumber++) {
	If ((($lineNumber - 1) % $logLineCadence) -Eq 0) {
		[string]$logLineInfo = "Generating line #$($lineNumber.ToString($numberLogFormat))/$($numberOfLines.ToString($numberLogFormat))"
		If ($logLineCadence -Gt 1) {
			$logLineInfo = "$($logLineInfo) (cadence $($logLineCadence.ToString($numberLogFormat)))"
		}
		If ($numberOfRandomWords -Gt 0 -And $randomWordLength -Gt 0) {
			$logLineInfo = "$($logLineInfo) with $($numberOfRandomWords) random word(s) of length $($randomWordSizeString)"
		} Else {
			$logLineInfo = "$($logLineInfo) without any random words"
		}
		Log Info $logLineInfo
	}

	# Add ID as the first item, w/o delimiter
	AppendItem -sb $bufferSb -item $lineNumber.ToString()

	# Add a three-alpha-letter code for each line, as the second item
	$code = [string]::new((Get-Random -InputObject $alphaLetters -Count 3))
	AppendItem -sb $bufferSb -item $code -delimiter $itemDelimiter

	For ($addedWords = 0; $addedWords -Lt $numberOfRandomWords; $addedWords++) {
		# Add delimiter before creating the next random word
		AppendItem -sb $bufferSb -delimiter $itemDelimiter

		$currentWordLength = 0
		While ($currentWordLength -Lt $randomWordLength) {
			# Randomize the letters array and append to the random word builder
			$letterLimit = [Math]::Min($randomWordLength - $currentWordLength, $alphaNumLetters.Count)
			$randomLetters = [string]::new((Get-Random -InputObject $alphaNumLetters -Count $letterLimit))
			$currentWordLength += $randomLetters.Length
			AppendItem -filePath $filePath -fileWriteThreshold $fileWriteThreshold -sb $bufferSb -item $randomLetters
		}
	}

	AppendItem -sb $bufferSb -item ([System.Environment]::NewLine)
}

# Force file write (as the threshold is 0) at the end,
# w/ the remaining string builder value, w/o appending any more items
AppendItem -filePath $filePath -fileWriteThreshold 0 -sb $bufferSb

Log Success "Result file @ [$((Resolve-Path -Path $filePath).Path)]"