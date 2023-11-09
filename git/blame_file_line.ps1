Param(
	[Parameter(Mandatory=$True, HelpMessage="File path to check git history")]
	[ValidateNotNullOrEmpty()]
	[string]$filePath,

	[Parameter(Mandatory=$True, HelpMessage="Starting line number (1-based)")]
	[UInt32]$startLine,

	[Parameter(Mandatory=$False, HelpMessage="Ending line number (1-based)")]
	[UInt32]$endLine = 0,

	[Parameter(Mandatory=$False, HelpMessage="Earliest date for which to check git history")]
	[AllowNull()]
	[AllowEmptyString()]
	[string]$after = $Null)

If (-Not (Test-Path -Path $filePath -PathType Leaf)) {
	Write-Host "File not found @ [$($filePath)]"
	return
}

If ($endLine -Lt $startLine) {
	$endLine = $startLine
}

[string]$command = "git log -L $($startLine),$($endLine):$($filePath)"
If (-Not [string]::IsNullOrEmpty($after)) {
	$command += " --after=$($after)"
}

Write-Host "Running command:`n`t$($command)"
Invoke-Expression $command
