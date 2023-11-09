[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Error number e.g. 3617")]
	[UInt32]$errorNumber,

	[Parameter(Mandatory=$False, HelpMessage="Target state value to display information for")]
	[AllowNull()]
	[AllowEmptyString()]
	[string]$targetState,

	[Parameter(Mandatory=$False, HelpMessage="DsMainDev repo path, defaulting to ROOT environment variable (set from CoreXT).")]
	[ValidateNotNullOrEmpty()]
	[string]$dsMainRepoPath = $env:ROOT,

	[Parameter(Mandatory=$False, HelpMessage="Search subfolder.")]
	[ValidateNotNullOrEmpty()]
	[string]$searchSubfolder = "Sql",

	[Parameter(Mandatory=$False, HelpMessage="Should we list all files where an error state is thrown")]
	[switch]$includeFileInfo,

	[Parameter(Mandatory=$False, HelpMessage="Show debug logs (internal to this script)")]
	[switch]$showDebugLogs)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[string]$errorCode = & "$($PSScriptRoot)/sql_error_code.ps1" -errorNumber $errorNumber -dsMainRepoPath $dsMainRepoPath
If ([string]::IsNullOrWhiteSpace($errorCode)) {
	return
}

& "$($PSScriptRoot)/sql_error_states_by_code.ps1" -errorCode $errorCode `
	-targetState $targetState `
	-dsMainRepoPath $dsMainRepoPath `
	-searchSubfolder $searchSubfolder `
	-includeFileInfo:$includeFileInfo.IsPresent `
	-showDebugLogs:$showDebugLogs.IsPresent
