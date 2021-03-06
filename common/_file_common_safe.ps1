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
