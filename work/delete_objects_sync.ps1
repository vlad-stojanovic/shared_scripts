Param(
	[Parameter(Mandatory=$True, HelpMessage="Directories to delete, absolute or relative paths")]
	[string[]]$dirsToDelete,

	[Parameter(Mandatory=$False, HelpMessage="Common root directory for all the relative paths provided")]
	[string]$rootDir)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

ForEach ($dir in $dirsToDelete) {
	[string]$targetDir = $dir
	If (-Not [string]::IsNullOrWhiteSpace($rootDir)) {
		$targetDir = Join-Path -Path $rootDir -ChildPath $dir
	}

	If (Test-Path -Path $targetDir -PathType Container) {
		# Do not use Remove-Item because of issues with symlinks in older PS versions (fixed in Dec 2019)
		# https://github.com/PowerShell/PowerShell/issues/621
		# Ignore return value for RunCommand
		RunCommand "RD /Q/S `"$($targetDir)`"" -useCmd -silentCommandExecution | Out-Null
	} Else {
		Log Verbose "Folder does not exist [$($targetDir)]"
	}
}
