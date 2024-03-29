# File includes common file helper functions that are guaranteed not to exit the calling scope
# and are therefore safe to be used in other functions, scripts, etc.
# NOTE: Do not use Log functions (defined elsewhere) because of potential circular dependency, use Write-Host instead.

function AddFullAccessToUser() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="File system path (file or directory)")]
		[ValidateNotNullOrEmpty()]
		[string]$path,

		[Parameter(Mandatory=$True, HelpMessage="User identity in the format DOMAIN\USERNAME")]
		[ValidateNotNullOrEmpty()]
		[string]$userIdentity)
	Write-Host "Granting full access control to user [$($userIdentity)] on [$($path)]"
	[System.Security.AccessControl.FileSystemSecurity]$acl = Get-ACL -Path $path
	$acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($userIdentity, "FullControl", "Allow"))
	Set-Acl -Path $path -AclObject $acl
}

function AddFullAccessToCurrentUser() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="File system path (file or directory)")]
		[ValidateNotNullOrEmpty()]
		[string]$path)
	AddFullAccessToUser -path $path -userIdentity "$($env:USERDOMAIN)\$($env:USERNAME)"
}

function CreateDirectoryIfNotExists() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Directory path")]
		[ValidateNotNullOrEmpty()]
		[string]$dirPath)
	If (Test-Path -Path $dirPath) {
		# Directory already exists, nothing more to do.
		return
	}

	Write-Host "Creating new directory [$($dirPath)]"
	New-Item -Path $dirPath -ItemType Directory -Force | Out-Null
	AddFullAccessToCurrentUser -path $dirPath
}

function CreateFileIfNotExists() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="File path")]
		[ValidateNotNullOrEmpty()]
		[string]$filePath)
	# Note: Do not use Log functions (defined below) as that may cause an infinite loop when creating log files.
	If (Test-Path -Path $filePath) {
		# File already exists, nothing more to do.
		return
	}

	# File does not exist, check for its directory
	# as file creation will fail if the parent directory does not exist.
	CreateDirectoryIfNotExists -dirPath (Split-Path -Path $filePath -Parent)

	# At this point - the parent directory exists, but the file does not - create it.
	Write-Host "Creating new empty file [$($filePath)]"
	New-Item -Path $filePath -ItemType File -Force | Out-Null
	AddFullAccessToCurrentUser -path $filePath
}

function CreateJunction() {
	[OutputType([System.Void])]
	[Alias("CreateHardLink")]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Junction (hard link) destination path")]
		[ValidateNotNullOrEmpty()]
		[string]$junctionPath,

		[Parameter(Mandatory=$True, HelpMessage="Source (original file/directory) path")]
		[ValidateNotNullOrEmpty()]
		[string]$sourcePath)
	If (Test-Path -Path $junctionPath) {
		Write-Host "Junction path already exists @ [$($junctionPath)]"
		return
	}

	Write-Host "Creating new junction [$($junctionPath)] -> [$($sourcePath)]"
	New-Item -ItemType Junction -Path $junctionPath -Target $sourcePath -Force | Out-Null
}

function CreateShortcut() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Shortcut destination path")]
		[ValidateNotNullOrEmpty()]
		[string]$shortcutPath,

		[Parameter(Mandatory=$True, HelpMessage="Target application")]
		[ValidateNotNullOrEmpty()]
		[string]$target,

		[Parameter(Mandatory=$False, HelpMessage="Target arguments")]
		[AllowNull()]
		[string]$arguments = $Null)
	[string]$extension = [System.IO.Path]::GetExtension($shortcutPath)
	[string]$correctExtension = ".lnk"
	If ([string]::IsNullOrEmpty($extension)) {
		$shortcutPath = "$($shortcutPath)$($correctExtension)"
	} ElseIf ($extension -INe $correctExtension) {
		Log Error "Incorrect extension for a shortcut [$($shortcutPath)]"
		return
	}

	If (Test-Path -Path $shortcutPath) {
		Log Warning "Shortcut already exists @ [$($shortcutPath)]"
		return
	}

	[object]$wsShell = New-Object -comObject WScript.Shell
	[object]$shortcut = $wsShell.CreateShortcut($shortcutPath)
	$shortcut.TargetPath = $target
	If (-Not [string]::IsNullOrEmpty($arguments)) {
		$shortcut.Arguments = $arguments
	}

	$shortcut.Save()
	Log Success "Created shortcut [$($shortcutPath)]" -additionalEntries @("'$($target) $($arguments)'") -entryPrefix "-> "
}

function IsChildPath() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Item path")]
		[ValidateNotNullOrEmpty()]
		[string]$itemPath,

		[Parameter(Mandatory=$True, HelpMessage="Potential root paths")]
		[AllowNull()]
		[AllowEmptyCollection()]
		[string[]]$rootPaths)
	If ($Null -Eq $rootPaths) {
		return $False
	}

	[string]$resolvedItemPath = Resolve-Path -Path $itemPath
	If ([string]::IsNullOrEmpty($resolvedItemPath)) {
		return $False
	}

	# Add a path terminator suffix as we want to use StartsWith,
	# otherwise "Parent" and "Parent1" would both be reported as root paths of "Parent\item.txt".
	[string[]]$existingParentPaths = $rootPaths |
		ForEach-Object { (Get-Item -Path "$($_)$([System.IO.Path]::DirectorySeparatorChar)" -ErrorAction Ignore).FullName } |
		Where-Object { $Null -Ne $_ } |
		Where-Object { $resolvedItemPath.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) }
	return $existingParentPaths.Count -Gt 0
}
