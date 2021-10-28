Param(
	[Parameter(Mandatory=$True)]
	[string[]]$dirsToDelete,

	[Parameter(Mandatory=$False)]
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
		RunCommand "CMD /C 'RD /Q/S `"$($targetDir)`"'" -silentCommandExecution
	} Else {
		LogInfo "Folder does not exist [$($targetDir)]"
	}
}
