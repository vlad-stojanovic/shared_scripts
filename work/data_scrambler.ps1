[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Input data file to be scrambled")]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$False, HelpMessage="Intermediate Byte storage size")]
	[Int32]$byteStorageSize = 1000 * 1000)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[Byte[]]$ignoredBytes = @(
	, 0x0D # '\r'
	, 0x0A # '\n'
	, [Byte][char]' '
	, [Byte][char]','
	, [Byte][char]'"'
	, [Byte][char]'T' # For timestamps e.g. "2000-01-01T00:00:00Z"
	, [Byte][char]'Z' # For timestamps e.g. "2000-01-01T00:00:00Z"
	, [Byte][char]'A' # For timestamps e.g. "1/10/2000 00:00:00 AM
	, [Byte][char]'M' # For timestamps e.g. "1/10/2000 00:00:00 PM
	, [Byte][char]'P' # For timestamps e.g. "1/10/2000 00:00:00 PM
)

function getReplacement() {
	[OutputType([Byte])]
	Param(
		[Byte]$value)
	If ($ignoredBytes -contains $value) {
		return $value # No replacement for these Bytes
	}

	# Single-byte/ASCII processing - bytes (0-127)

	If ($value -Ge [Byte][char]'A' -And $value -Le [Byte][char]'Z') {
		return [Byte][char]'A' # Uppercase ASCII letter replacement
	}
	If ($value -Ge [Byte][char]'a' -And $value -Le [Byte][char]'z') {
		return [Byte][char]'a' # Lowercase ASCII letter replacement
	}
	If ($value -Ge [Byte][char]'0' -And $value -Le [Byte][char]'9') {
		return [Byte][char]'1' # Number replacement - only '1' can provide valid dates & times e.g. 11/1/1111 11:11
	}
	If ($value -Ge 0x00 -And $value -Le 0x7F) {
		return $value # Other (previously unprocessed) single-byte/ASCII characters
	}

	# Multi-byte/UNICODE processing, leading bytes (192-255) and continuation bytes (128-191)
	# Note that values larger than 247 is ignored in the rules (will not be replaced),
	# as the maximum size of UTF-8 character should be 4B.

	If ($value -Ge 0x80 -And $value -Le 0xBF) {
		return 0x81 # Multi-byte continuation byte (binary 10000001)
	}

	If ($value -Ge 0xC0 -And $value -Le 0xDF) {
		return 0xC3 # Two-byte-char leading byte (binary 11000011)
	}
	If ($value -Ge 0xE0 -And $value -Le 0xEF) {
		return 0xE3 # Three-byte-char leading byte (binary 11100011)
	}
	If ($value -Ge 0xF0 -And $value -Le 0xF7) {
		return 0xF3 # Four-byte-char leading byte (binary 11110011)
	}

	# If no rules were matched - return original input
	return $value
}

If (-Not (Test-Path -Path $filePath -PathType Leaf)) {
	ScriptFailure "Data file does not exist @ [$($filePath)]"
}

[string]$absFilePath = Resolve-Path -Path $filePath
$inputFileStream = [System.IO.FileStream]::new($absFilePath, [System.IO.FileMode]::Open)
If ($Null -Eq $inputFileStream) {
	ScriptFailure "Opening input stream failed [$($absFilePath)]"
}

[string]$scrambledOutputPath = "$($absFilePath).scrambled"
$outputFileStream = [System.IO.FileStream]::new($scrambledOutputPath, [System.IO.FileMode]::Append)
If ($Null -Eq $outputFileStream) {
	ScriptFailure "Opening output stream failed [$($scrambledOutputPath)]"
}

If ($outputFileStream.Position -Gt 0) {
	If ($outputFileStream.Position -Ne $inputFileStream.Seek($outputFileStream.Position, [System.IO.SeekOrigin]::Begin)) {
		$outputFileStream.Close()
		ScriptFailure "Setting input stream to position $(GetSizeString -size $outputFileStream.Position) failed"
	}
}

# Take at least 1KB for Byte storage size.
[Byte[]]$byteStorage = New-Object Byte[] ([Math]::Max($byteStorageSize, 1000))
Log Info "Reading $(GetSizeString -size $inputFileStream.Length -unit 'B') data from position $(GetSizeString -size $outputFileStream.Position) via storage of $(GetSizeString -size $byteStorage.Length -unit 'B')"
Do {
	[Int]$readBytes = $inputFileStream.Read($byteStorage, 0, $byteStorage.Length)
	If ($readBytes -Le 0) {
		# On EOF we will return 0 bytes read. Negative values are not expected.
		If ($readBytes -Lt 0) {
			Log Error "Failed to read ($($readBytes)) from file [$($absFilePath)]"
		}

		break;
	}

	For ([Int]$i = 0; $i -Lt $readBytes; $i++) {
		$byteStorage[$i] = getReplacement -value ($byteStorage[$i])
	}

	$outputFileStream.Write($byteStorage, 0, $readBytes)
	Log Info "Written $(GetSizeString -size $readBytes)/$(GetSizeString -size $outputFileStream.Position)/$(GetSizeString -size $inputFileStream.Length) Bytes ($(GetSizeString -size ($outputFileStream.Position / ($inputFileStream.Length / 100)) -unit '%')) `n`tto file [$($scrambledOutputPath)]"
} While (-Not $inputFileStream.EndOfStream)

$outputFileStream.Flush()

If ($inputFileStream.Length -Ne $outputFileStream.Length) {
	Log Error "Data size mismatch`n`tfrom $(GetSizeString -size $inputFileStream.Length -unit 'B') file [$($absFilePath)]`n`tto $(GetSizeString -size $outputFileStream.Length -unit 'B') file [$($scrambledOutputPath)]"
} Else {
	Log Success "Scrambled all $(GetSizeString -size $outputFileStream.Length -unit 'B') of data`n`tfrom file [$($absFilePath)]`n`tto file [$($scrambledOutputPath)]"
}

$outputFileStream.Close()
$inputFileStream.Close()
