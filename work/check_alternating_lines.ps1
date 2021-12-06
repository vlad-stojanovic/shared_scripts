[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True)]
	[ValidateNotNullOrEmpty()]
	[string]$directory,

	[Parameter(Mandatory=$False, HelpMessage="Output file path prefix")]
	[string]$filePathPrefix = $Null,

	[Parameter(Mandatory=$False, HelpMessage="Output file extension e.g. 'csv'")]
	[string]$fileExtension = "csv",

	[Parameter(Mandatory=$True)]
	[UInt64]$expectedLobLength = 100,

	[Parameter(Mandatory=$False)]
	[UInt16]$expectedLobCount = 1,

	[Parameter(Mandatory=$False)]
	[UInt32]$expectedLineCount = 10)

[int]$global:FileWriteCount = 0

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[string]$expectedLobLengthStr = GetSizeString -size $expectedLobLength -unit "B"

[string]$fileName = "$($filePathPrefix)lob-$($expectedLobLengthStr)_columns-$($expectedLobCount)_lines-$(GetSizeString -size $expectedLineCount)"
[string]$filePath = "$($directory)\$($fileName).$($fileExtension)"
If (-Not (Test-Path -Path $filePath -PathType Leaf)) {
	ScriptFailure "File does not exist @ [$($filePath)]"
}

$reader = New-Object IO.StreamReader $filePath
$reader.ReadLine() | Out-Null # Ignore the header line
[UInt32]$lineCounter = 0
[bool]$invalidLineFound = $False
while(!$reader.EndOfStream) {
	$lineCounter++
	[string]$rowValue = $reader.ReadLine() # -replace "^\d+,[0-9Nan]+,",""
	[string[]]$columnLengths = $rowValue -split "," | ForEach-Object { $_.Length }
	LogInfo "Row #$($lineCounter) (length $($rowValue.Length)) has $($columnLengths.Length) columns"

	[HashTable]$lengthMap = @{}
	For ([int]$ci = 0; $ci -Lt $columnLengths.Length; $ci++) {
		[string]$columnLength = $columnLengths[$ci]
		If ($lengthMap[$columnLength] -Gt 0) {
			$lengthMap[$columnLength]++
		} Else {
			$lengthMap[$columnLength] = 1
		}
	}

	Write-Host "`t" -NoNewLine
	[bool]$foundExpectedLobSize = $False
	ForEach ($key in ($lengthMap.Keys | Sort-Object)) {
		[int]$value = $lengthMap[$key]
		[string]$message = "$(GetSizeString -size ([UInt32]$key) -unit 'B') x $($value), "
		If ($key -Eq $expectedLobLength.ToString()) {
			$foundExpectedLobSize = $True
			If ($value -Eq $expectedLobCount) {
				Write-Host $message -NoNewLine -ForeGroundColor Green
			} Else {
				Write-Host $message -NoNewLine -ForeGroundColor Red
				$invalidLineFound = $True
			}
		} Else {
			Write-Host $message -NoNewLine
		}
	}

	LogNewLine
	If (-Not $foundExpectedLobSize) {
		$invalidLineFound = $True
		LogError "Did not find expected LOB size $($expectedLobLengthStr)"
	}

	If ($invalidLineFound) {
		[string]$errorFilePath = "$($directory)\$($fileName)_invalid-row-$($lineCounter).txt"
		LogInfo "Logging row contents @ [$($errorFilePath)]"
		$rowValue | Out-File -FilePath $errorFilePath -Encoding Ascii
		break # Don't read anymore - the file contents are incorrect
	}
}

$reader.Close()

If ($invalidLineFound -Or $lineCounter -Ne $expectedLineCount) {
	ScriptFailure "Did not find expected number of lines $($expectedLineCount)"
}

ScriptExit -exitStatus 0 -message "File [$($filePath)] contents are as expected"