[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Error number e.g. 3617")]
	[UInt32]$errorNumber,

	[Parameter(Mandatory=$False, HelpMessage="DsMainDev repo path, defaulting to ROOT environment variable (set from CoreXT).")]
	[ValidateNotNullOrEmpty()]
	[string]$dsMainRepoPath = $env:ROOT)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[string]$sqlErrorCodesPath = Join-Path -Path $dsMainRepoPath -ChildPath "Sql\Ntdbms\include\sqlerrorcodes.h"

Log Verbose "Searching for error number #$($errorNumber) in [$($sqlErrorCodesPath)]"

[Microsoft.PowerShell.Commands.MatchInfo]$errorNumberMatch = Select-String -Pattern "ErrorNumber:\s*$($errorNumber)\b" -Path $sqlErrorCodesPath -Context 0,20
If ($Null -Eq $errorNumberMatch) {
	Log Error "Did not find error definition"
	return $Null
}

# Error number can be used as either the full value, or just the last two digits
[Microsoft.PowerShell.Commands.MatchInfo]$errorCodeMatch = $errorNumberMatch.Context.PostContext |
	Select-String -Pattern "const int (\w+) = (($($errorNumber))|($($errorNumber % 100)))"
If ($Null -Eq $errorCodeMatch) {
	Log Error "Did not find error code details within [$($errorNumberMatch)]"
	return $Null
}

[string]$errorCode = $errorCodeMatch.Matches[0].Groups[1].Value
If ([string]::IsNullOrWhiteSpace($errorCode)) {
	Log Error "Did not find error code group within [$($errorCodeMatch)]"
	return $Null
}

Log Success "Found error code [$($errorCode)] for number #$($errorNumber)"
LogNewLine
return $errorCode
