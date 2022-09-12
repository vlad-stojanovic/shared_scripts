Param(
	[Parameter(Mandatory=$True, HelpMessage="Objects to delete, absolute paths or relative to the `$rootDir")]
	[string[]]$objectsToDelete,

	[Parameter(Mandatory=$False, HelpMessage="Common root directory for all the relative paths provided")]
	[string]$rootDir)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

ForEach ($object in $objectsToDelete) {
	[string]$targetPath = $object
	If (-Not [string]::IsNullOrWhiteSpace($rootDir)) {
		$targetPath = Join-Path -Path $rootDir -ChildPath $targetPath
	}

	# Prefix the path with "\\?\" for any potential files with invalid names e.g. ending with ".."
	# https://stackoverflow.com/questions/4075753/how-to-delete-a-folder-that-name-ended-with-a-dot
	[string]$fullDeleteTargetPath = "`"\\?\$($targetPath)`""
	# Do not use Remove-Item (but CMD commands) because of issues with symlinks in older PS versions (fixed in Dec 2019)
	# https://github.com/PowerShell/PowerShell/issues/621
	# Ignore return value for RunCommand
	If (Test-Path -Path $targetPath -PathType Container) {
		RunCommand "RD /Q/S $($fullDeleteTargetPath)" -useCmd -silentCommandExecution | Out-Null
	} ElseIf (Test-Path -Path $targetPath -PathType Leaf) {
		RunCommand "DEL /F $($fullDeleteTargetPath)" -useCmd -silentCommandExecution | Out-Null
	}Else {
		Log Verbose "Object does not exist [$($targetPath)]"
	}
}
