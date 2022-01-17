[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Module name RegEx pattern e.g. '^prefix', 'suffix$', '^fullName$'")]
	[ValidateNotNullOrEmpty()]
	[string]$moduleNameRegExPattern)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function removeModules() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$moduleNames)

	Remove-Module -Name $moduleName -ErrorAction SilentlyContinue
	Log Warning "Attempting to uninstall module: $($moduleName)" -indentLevel 1
	Uninstall-Module -Name $moduleName -AllVersions
}

[Object[]]$modules = Get-InstalledModule |
	Where-Object { $_.Name -imatch $moduleNameRegExPattern }

[string]$modulesMsg = $Null
If ($modules.Count -Eq 0) {
	ScriptFailure "No modules found with RegEx '$($moduleNameRegExPattern)'"
} ElseIf ($modules.Count -Eq 1) {
	$modulesMsg = "target module '$($modules[0].Name)'"
} Else {
	$modulesMsg = "$($modules.Count) target modules"
}

Log Info "Searching for dependencies of $($modulesMsg)"
[string[]]$dependencyModuleNames = $modules |
	ForEach-Object {
		[string]$moduleInfoPath = Join-Path -Path $_.InstalledLocation -ChildPath PSGetModuleInfo.xml
		[Object]$moduleInfo = Import-Clixml -Path $moduleInfoPath
		$moduleInfo.Dependencies.Name
	} |
	Sort-Object -Descending -Unique

$dependencyModuleNames 
exit

If ($dependencyModuleNames.Count -Gt 0) {
	Log Warning "Removing $($dependencyModuleNames.Count) dependency modules of $($modulesMsg)"
	$dependencyModuleNames | ForEach-Object { removeModule -moduleName $_ }
} Else {
	Log Verbose "No dependencies found for $($modulesMsg)"
}

Log Warning "Removing $($modulesMsg)"
$modules | ForEach-Object { removeModule -moduleName $_.Name }