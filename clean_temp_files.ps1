Param(
	[Parameter(Mandatory=$False, HelpMessage="Number of days to preserve recent temp files for (set to 0 to delete all files)")]
	[Byte]$daysToKeepFiles = 7,

	[Parameter(Mandatory=$False, HelpMessage="Confirm deletion prior to deleting each temp resource")]
	[switch]$confirm)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

function deleteTempEntities() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$tempFileDir,

		[Parameter(Mandatory=$True)]
		[ValidateSet("file", "dir")]
		[string]$entityType)
	# Take entries based on write (update) times. Directories will get updated with each file added to them.
	[System.IO.FileSystemInfo[]]$tempInfos =
		Get-ChildItem -Path $tempFileDir -Recurse -File:($entityType -IEq "file") -Directory:($entityType -IEq "dir") |
			Where-Object { $_.LastWriteTime -Le (Get-Date).AddDays(-$daysToKeepFiles) }
	If ($tempInfos.Count -Gt 0) {
		ForEach ($tempInfo in $tempInfos) {
			# Check whether we have already deleted the entity (by previously deleting its parent directory)
			If (Test-Path -Path $tempInfo.FullName) {
				If ((-Not $confirm.IsPresent) -Or (ConfirmAction "Delete temp $($entityType) [$($tempInfo.FullName)], created @ $($tempInfo.CreationTime)" -defaultYes)) {
					Log Verbose "Deleting $($entityType) [$($tempInfo.FullName)] (modified @ $($tempInfo.LastWriteTime))"
					Remove-Item -Path $tempInfo.FullName -Recurse:($entityType -IEq "dir") -Force
				}
			}
		}
	} Else {
		Log Success "No temp $($entityType)s older than $($daysToKeepFiles) day(s) found in [$($tempFileDir)]"
	}
}

[string[]]$tempFileDirectories = @(
	(Join-Path -Path $PSScriptRoot -ChildPath "cache"),
	(Join-Path -Path $PSScriptRoot -ChildPath "logs")
)
ForEach ($tempFileDir in $tempFileDirectories) {
	If (Test-Path -Path $tempFileDir) {
		# First delete any directories that are old enough, then files
		deleteTempEntities -tempFileDir $tempFileDir -entityType "dir"
		deleteTempEntities -tempFileDir $tempFileDir -entityType "file"
	} Else {
		Log Info "Temp file directory does not exist [$($tempFileDir)]"
	}
}