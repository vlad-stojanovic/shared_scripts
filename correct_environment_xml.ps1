[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Path to TestShell environment XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$environmentFilePath,

	[Parameter(Mandatory=$True, HelpMessage="Path to Provisioned services XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$provisionedServicesPath)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

If (-Not (Test-Path -Path $environmentFilePath)) {
	ScriptFailure "Environment config file [$($environmentFilePath)] does not exist"
}

If (-Not (Test-Path -Path $provisionedServicesPath)) {
	ScriptFailure "Provisioned services file [$($provisionedServicesPath)] does not exist"
}

[Xml]$environmentXml = Get-Content -Path $environmentFilePath
[System.Xml.XmlElement[]]$allServerConnectionInfos = $environmentXml.TestShellEnvironment.EnvironmentComponent.ProvisionedServers.CloudServerConnectionInfo
[Xml]$provisionedServicesXml = Get-Content -Path $provisionedServicesPath
[System.Xml.XmlElement[]]$allProvisionedServiceInfos = $provisionedServicesXml.ProvisionedServices

ForEach ($serverConnectionInfo in $allServerConnectionInfos) {
	LogNewLine
	[string]$serverName = $serverConnectionInfo.Name
	[string]$serverType = $serverConnectionInfo.ServerType
	[string]$serviceDebugInfo = "'$($serverName)' ($($serverType))"

	[System.Xml.XmlElement[]]$targetProvisionedServiceInfos = $Null
	switch ($serverType) {
		"PolarisPool" {
			$targetProvisionedServiceInfos = $allProvisionedServiceInfos.PolarisPools.PolarisPool
			break
		}
		"LogicalServer" {
			$targetProvisionedServiceInfos = $allProvisionedServiceInfos.LogicalServers.LogicalServer
			break
		}
		"ManagedServer" {
			$targetProvisionedServiceInfos = $allProvisionedServiceInfos.ManagedServers.ManagedServer
			break
		}
		default {
			ScriptFailure "Unknown type for $($serviceDebugInfo)"
			break
		}
	}

	[System.Xml.XmlElement[]]$targetProvisionedServiceInfo = $targetProvisionedServiceInfos |
		Where-Object { $_.Name -IEq $serverName } |
		Select-Object -First 1
	If ($Null -Eq $targetProvisionedServiceInfo) {
		ScriptFailure "No info found for $($serviceDebugInfo) in [$($provisionedServicesPath)]"
	}

	[string]$subscriptionId = $targetProvisionedServiceInfo.SubscriptionId
	[string]$username = $targetProvisionedServiceInfo.Username
	[string]$password = $targetProvisionedServiceInfo.Password

	If ([string]::IsNullOrWhiteSpace($subscriptionId)) {
		ScriptFailure "No customer subscription ID found for $($serviceDebugInfo)"
	} ElseIf ([string]::IsNullOrWhiteSpace($username)) {
		ScriptFailure "Unable to find username for $($serviceDebugInfo)"
	} ElseIf ([string]::IsNullOrWhiteSpace($password)) {
		ScriptFailure "Unable to find password for $($serviceDebugInfo)"
	}

	$serverConnectionInfo.SubscriptionId = $subscriptionId
	$serverConnectionInfo.UserName = $username
	$serverConnectionInfo.Password = $password
	LogSuccess (@(
		"Updated for $($serviceDebugInfo)",
		"subscription ID: '$($subscriptionId)'",
		"user name: '$($username)'",
		"password: '$($password)'") -join "`n`t- ")
}

LogNewLine
$environmentXml.Save($environmentFilePath)
LogSuccess "Updated environment file [$($environmentFilePath)]"