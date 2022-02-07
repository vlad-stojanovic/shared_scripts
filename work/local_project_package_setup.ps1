[CmdletBinding()]
Param (
	[Parameter(Mandatory=$True, HelpMessage="Path to local build output directory")]
	[ValidateNotNullOrEmpty()]
	[string]$localBuildOutputPath,

	[Parameter(Mandatory=$True, HelpMessage="Path to package config file (in the project)")]
	[ValidateNotNullOrEmpty()]
	[string]$projectPackageConfigPath,

	[Parameter(Mandatory=$True, HelpMessage="Package full name (ID) (in the project)")]
	[ValidateNotNullOrEmpty()]
	[string]$packageFullName,

	[Parameter(Mandatory=$True, HelpMessage="Path to the Nuget cache root directory")]
	[ValidateNotNullOrEmpty()]
	[string]$nugetCacheRootPath,

	[Parameter(Mandatory=$False, HelpMessage="Subfolder/subpath to build drop in the Nuget package directory")]
	[string]$nugetPackageBuildDropSubfolder,
	
	[Parameter(Mandatory=$False, HelpMessage="Modify the local Nuget package path by adding this suffix. Check whether the build supports the provided version suffix for Nuget packages")]
	[string]$nugetPackageLocalVersionSuffix = $Null)
	
# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

[XML]$config = Get-Content -Path $projectPackageConfigPath
[System.Xml.XmlElement[]]$configPackages = $config.packages.package | Where-Object { $_.id -IEq $packageFullName }
If (-Not (CheckEntryCount -entries $configPackages -description "$($packageFullName) packages" -location $projectPackageConfigPath)) {
	return
}

[string]$versionCache = $configPackages[0].version
[string]$versionLocal = $versionCache
If ([string]::IsNullOrWhiteSpace($nugetPackageLocalVersionSuffix) -Or $versionLocal.EndsWith($nugetPackageLocalVersionSuffix)) {
	Log Info "$($packageFullName) local version already correct [$($versionLocal)]"
} Else {
	$versionLocal = "$($versionLocal)$($nugetPackageLocalVersionSuffix)"
	Log Warning "Replacing $($packageFullName) local version [$($versionLocal)]"
	$configPackages[0].version = $versionLocal
	$config.Save($projectPackageConfigPath)
}

[string]$packageLocalPath = Join-Path -Path $nugetCacheRootPath -ChildPath "$($packageFullName).$($versionLocal)"
If (Test-Path -Path $packageLocalPath) {
	Log Verbose "Package cache already exists" -additionalEntries @("@ [$($packageLocalPath)]")
} Else {
	[string]$packageCachePath = Join-Path -Path $nugetCacheRootPath -ChildPath "$($packageFullName).$($versionCache)"
	If (Test-Path -Path $packageCachePath) {
		Log Info "Copying package cache" -additionalEntries @("[$($packageCachePath)]", "-> [$($packageLocalPath)]")
		Copy-Item -Force -Recurse -Path $packageCachePath -Destination $packageLocalPath
	} Else {
		Log Info "Creating package cache" -additionalEntries @("@ [$($packageLocalPath)]")
		New-Item -Path $packageLocalPath -ItemType Directory -Force | Out-Null
	}
}

[string]$packageLocalBuildDropPath = $packageLocalPath
If (-Not [string]::IsNullOrWhiteSpace($nugetPackageBuildDropSubfolder)) {
	$packageLocalBuildDropPath = Join-Path -Path $packageLocalBuildDropPath -ChildPath $nugetPackageBuildDropSubfolder
}

If (Test-Path -Path $packageLocalBuildDropPath) {
	Log Warning "Replacing $($packageFullName) build files" -additionalEntries @("[$($localBuildOutputPath)]", "-> [$($packageLocalBuildDropPath)]")
	Remove-Item -Recurse -Path $packageLocalBuildDropPath -ErrorAction Ignore
} Else {
	Log Info "Copying $($packageFullName) build files" -additionalEntries @("-> [$($packageLocalBuildDropPath)]")
}

Copy-Item -Recurse -Force -Path $localBuildOutputPath -Destination $packageLocalBuildDropPath
