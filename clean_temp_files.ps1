Param(
	[Parameter(Mandatory=$False, HelpMessage="Number of days to preserve recent temp files for (set to 0 to delete all files)")]
	[Byte]$daysToKeepFiles = 7)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

[string[]]$tempFileDirectories = @(
	(Join-Path -Path $PSScriptRoot -ChildPath "cache"),
	(Join-Path -Path $PSScriptRoot -ChildPath "logs")
)
ForEach ($tempFileDir in $tempFileDirectories) {
	If (Test-Path -Path $tempFileDir) {
		[System.IO.FileSystemInfo[]]$tempFileInfos = 
			Get-ChildItem -Path $tempFileDir |
				Where-Object {
					$_.CreationTime -Le (Get-Date).AddDays(-$daysToKeepFiles)
				}
		If ($tempFileInfos.Count -Gt 0) {
			ForEach ($tempFileInfo in $tempFileInfos) {
				Log Verbose "Deleting temp file [$($tempFileInfo.FullName)]" -additionalEntries @("created @ $($tempFileInfo.CreationTime)")
				Remove-Item -Path $tempFileInfo.FullName -Force
			}
		} Else {
			Log Success "No temp files older than $($daysToKeepFiles) day(s) found in [$($tempFileDir)]"
		}
	} Else {
		Log Info "Temp file directory does not exist [$($tempFileDir)]"
	}
}