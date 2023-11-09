Param(
	[Parameter(Mandatory=$True, HelpMessage="Base/'OLD' branch name (e.g. a snap for release)")]
	[ValidateNotNullOrEmpty()]
	[string]$snapBranchName,

	[Parameter(Mandatory=$False, HelpMessage="Updated/'NEW' branch name (with more commits than the base branch e.g. master/main)")]
	[ValidateNotNullOrEmpty()]
	[string]$updatedBranchName = "master",

	[Parameter(Mandatory=$False, HelpMessage="VDW app type to search service setting diff")]
	[ValidateSet("Worker.VDW.Frontend", "Worker.VDW.Backend", "Worker.VDW.DQP", "Worker.VDW.Frontend.Trident", "Worker.VDW.Backend.Trident", "Worker.VDW.DQP.Trident")]
	[string]$vdwAppType = "Worker.VDW.Frontend",

	[Parameter(Mandatory=$False, HelpMessage="Show details about new settings")]
	[switch]$showNewSettings,

	[Parameter(Mandatory=$False, HelpMessage="Show most recent update (a specific git commit) details of FS definition")]
	[switch]$showUpdateDetails,

	[Parameter(Mandatory=$False, HelpMessage="Show debug logs (internal to this script)")]
	[switch]$showDebugLogs)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function getRemoteBranchName() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Branch name (possibly already remote)")]
		[ValidateNotNullOrEmpty()]
		[string]$branchName)
	[string]$remotePrefix = "origin/"
	If ($branchName.StartsWith($remotePrefix)) {
		return $branchName
	} Else {
		return "$($remotePrefix)$($branchName)"
	}
}

function downloadServiceSettingsFromRemote() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Branch name")]
		[ValidateNotNullOrEmpty()]
		[string]$branchName,

		[Parameter(Mandatory=$True, HelpMessage="Temp file path")]
		[ValidateNotNullOrEmpty()]
		[string]$tempFilePath)
	# Download file contents from remote (origin) branches
	[string]$remoteBranchName = getRemoteBranchName -branchName $branchName
	[string]$serviceSettingsRelativePath = "Sql/xdb/manifest/svc/sql/manifest/ServiceSettings_SQLServer_Common.xml"
	Log Verbose "Downloading service settings from branch [$($remoteBranchName)] into temp file [$($tempFilePath)]"
	Invoke-Expression -Command "git show $($remoteBranchName):$($serviceSettingsRelativePath) > $($tempFilePath)"
}

# Create temporary files for storing service settings per branch
[string]$snapServiceSettingsPath = (New-TemporaryFile).FullName
[string]$updatedServiceSettingsPath = (New-TemporaryFile).FullName

# Download service settings content into temp files
downloadServiceSettingsFromRemote -branchName $snapBranchName -tempFilePath $snapServiceSettingsPath
downloadServiceSettingsFromRemote -branchName $updatedBranchName -tempFilePath $updatedServiceSettingsPath

# Find the service setting differences
& "$($PSScriptRoot)/get_vdw_service_setting_diff.ps1" `
	-serviceSettingsOldXmlPath $snapServiceSettingsPath `
	-serviceSettingsNewXmlPath $updatedServiceSettingsPath `
	-newRemoteBranchName (getRemoteBranchName -branchName $updatedBranchName) `
	-vdwAppType $vdwAppType `
	-showNewSettings:$showNewSettings.IsPresent `
	-showUpdateDetails:$showUpdateDetails.IsPresent `
	-showDebugLogs:$showDebugLogs.IsPresent

# Cleanup of temp files
Remove-Item -Path $snapServiceSettingsPath -Force -ErrorAction Ignore
Remove-Item -Path $updatedServiceSettingsPath -Force -ErrorAction Ignore
