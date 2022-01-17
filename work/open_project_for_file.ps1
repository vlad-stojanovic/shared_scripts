Param(
	[Parameter(Mandatory=$True, HelpMessage="Starting/root directory to search the file in")]
	[ValidateNotNullOrEmpty()]
	[string]$startDir,

	[Parameter(Mandatory=$True, HelpMessage="File absolute path, file relative path (to `$startDir), or file name")]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$False, HelpMessage="Command to start the project e.g. 'start' will open it in Visual Studio (current default version)")]
	[string]$startProjectCmd = "start",

	[Parameter(Mandatory=$False, HelpMessage="Parent project that might contain the file's 'smaller' project")]
	[string[]]$parentProjects = @(),

	[Parameter(Mandatory=$False, HelpMessage="Print all the info during script execution, w/o actually running any commands")]
	[switch]$dryRun)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"
# Include find-project function
. "$($PSScriptRoot)/find_file_common_safe.ps1"

[string]$projectPath = find_project_for_file_in_start_dir -startDir $startDir -filePath $filePath
If ([string]::IsNullOrWhiteSpace($projectPath)) {
	ScriptFailure "Could not find project for file [$($filePath)] in [$($startDir)]"
}

ForEach ($parentProject in $parentProjects) {
	[string]$projectName = Split-Path -Path $projectPath -Leaf
	[string]$parentProjectPath = GetAbsolutePath $parentProject
	[string]$parentProjectName = [System.IO.Path]::GetFileNameWithoutExtension($parentProjectPath)
	If ($parentProjectPath -Ieq $projectPath) {
		Log Info "Parent project [$($parentProjectName)] is @ [$($projectPath)]"
	} ElseIf (Select-String -Path $parentProjectPath -Pattern $projectName -SimpleMatch -Quiet) {
		Log Info "Parent project [$($parentProjectName)] contains [$($projectName)]" -additionalEntries @("@ [$($parentProjectPath)]")
	}
}

[string]$command = "$($startProjectCmd) `"$($projectPath)`""
Log Info "Start project command" -additionalEntries @("$($command)`n")
If (-Not $dryRun.IsPresent) {
	Invoke-Expression -Command $command
}