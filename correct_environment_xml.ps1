[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Path to TestShell environment XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$environmentFilePath)

# Include common helper functions
. "$($PSScriptRoot)/../common/_common.ps1"

function getCmsQuery() {
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$serverType,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$serverName)

	[string]$cmsQuery = switch ($serverType) {
		"PolarisPool" { "SELECT TOP 1 subscription_id AS customer_subscription_id FROM vdw_pools WHERE vdw_pool_name = '$($serverName)'" }
		"LogicalServer" { "SELECT TOP 1 customer_subscription_id FROM logical_servers WHERE name = '$($serverName)'" }
		"ManagedServer" { "SELECT TOP 1 customer_subscription_id FROM managed_servers WHERE name = '$($serverName)'" }
		default { $Null }
	}

	If ([string]::IsNullOrWhiteSpace($cmsQuery)) {
		ScriptFailure "Server type [$($serverType)] is currently not supported with this script"
	}

	return $cmsQuery
}

If (-Not (Test-Path -Path $environmentFilePath)) {
	ScriptFailure "Environment config file [$($environmentFilePath)] does not exist"
}

[Xml]$environmentXml = Get-Content $environmentFilePath
[System.Xml.XmlElement[]]$allServerConnectionInfos = $environmentXml.TestShellEnvironment.EnvironmentComponent.ProvisionedServers.CloudServerConnectionInfo
$defaultServerConnectionInfo = $allServerConnectionInfos | `
	Where-Object { $_.IsDefault -IEq "true" -Or [string]::IsNullOrWhiteSpace($_.IsDefault) } | `
	Select-Object -First 1
If ($Null -Eq $defaultServerConnectionInfo) {
	ScriptFailure "No default server connection info found in [$($environmentFilePath)]"
}

[string]$cmsQuery = getCmsQuery -serverType $defaultServerConnectionInfo.ServerType -serverName $defaultServerConnectionInfo.Name
LogInfo "Getting subscription ID from local CMS with query:`n`t$($cmsQuery)"
$cmsResult = Invoke-Sqlcmd -ServerInstance "localhost,1437" -Database ClusterMetadataStore -Query $cmsQuery -QueryTimeout 10
If ($Null -Eq $cmsResult) {
	ScriptFailure "CMS query failed. Do you have:`n`t- OneBox deployed?`n`t- SqlServer module installed for PowerShell? You can do it via [Install-Module -Name SqlServer]"
}

[string]$subscriptionId = $cmsResult.customer_subscription_id
If ([string]::IsNullOrWhiteSpace($subscriptionId)) {
	ScriptFailure "No customer subscription ID found in local CMS"
}

LogSuccess "Found a subscription ID [$($subscriptionId)] in local CMS"

[string]$programData = $env:ProgramData
If ([string]::IsNullOrWhiteSpace($programData)) {
	$programData = "C:\ProgramData"
}
[string]$logDirectory = Join-Path -Path $programData -ChildPath "SqlDeploy\Logs"

LogInfo "Getting password from SQL deployment logs @ [$($logDirectory)]"

[string]$machineName = $env:COMPUTERNAME
If ([string]::IsNullOrWhiteSpace($machineName)) {
	$machineName = [System.Environment]::MachineName;
}
[string]$fileFilter = "oneboxdeploymentlog_$($machineName)-*"

$logFile = Get-ChildItem -Path $logDirectory -Filter $fileFilter | `
	# There may be many logs, check only the ones from the past 4 weeks
	Where-Object { $_.LastWriteTime -Gt (Get-Date).AddDays(-28) } | `
	# Find the file containing the current subscription id
	Where-Object { Select-String -Path $_.FullName -Pattern "sub:$($subscriptionId)" -SimpleMatch -Quiet } | `
	# Take the latest matching SQL deployment log
	Sort-Object -Property LastWriteTime -Descending | `
	Select-Object -First 1
If ([string]::IsNullOrWhiteSpace($logFile.FullName)) {
	ScriptFailure "Unable to find a SQL deployment log file`n`twith filter '$($fileFilter)'"
}

LogInfo "Found the latest SQL deployment log file`n`t[$($logFile.FullName)]`n`tmodified @ $($logFile.LastWriteTime)"

[System.Text.RegularExpressions.Match]$firstMatch =
	Select-String -Path $logFile.FullName `
		-Pattern "MgmtTest: Executing the command.*\buser:(\w{3,})\b.*\bpass:(\w{8,})\b" | `
	Select-Object -ExpandProperty Matches -First 1
[string]$username = $firstMatch.Groups[1].Value
[string]$password = $firstMatch.Groups[2].Value
If ([string]::IsNullOrWhiteSpace($username) -Or [string]::IsNullOrWhiteSpace($password)) {
	ScriptFailure "Unable to find username/password in the log file"
}

LogSuccess "Found a password [$($password)] in log file"

[string]$fileBackupPath = $environmentFilePath -replace "\.xml$","_$(Get-Date -Format "yyyy-MM-dd_HH-mm-ss").xml"
LogInfo "Backup environment file [$($fileBackupPath)]"
Copy-Item -Path $environmentFilePath -Destination $fileBackupPath

$allServerConnectionInfos | `
	ForEach-Object {
		$_.SubscriptionId = $subscriptionId
		$_.UserName = $username
		$_.Password = $password
	}

$environmentXml.Save($environmentFilePath)
LogSuccess "Updated environment file [$($environmentFilePath)]:`n`t- subscription ID [$($subscriptionId)]`n`t- username [$($username)]`n`t- password [$($password)]"