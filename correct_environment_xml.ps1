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

$wordReplacements = [System.Collections.ArrayList]::new()

function UpdateXmlValue() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="XML element to be updated")]
		[ValidateNotNull()]
		[System.Xml.XmlElement]$element,

		[Parameter(Mandatory=$True, HelpMessage="XML Property name to be updated")]
		[ValidateNotNullOrEmpty()]
		[string]$propertyName,

		[Parameter(Mandatory=$True, HelpMessage="New value for the XML property")]
		[ValidateNotNullOrEmpty()]
		[string]$newValue)
	If ([string]::IsNullOrWhiteSpace($newValue)) {
		ScriptFailure "No '$($propertyName)' new value provided"
	}

	[System.Xml.XmlNode]$propertyNode = $element.SelectSingleNode($propertyName)
	If ($Null -Eq $propertyNode) {
		ScriptFailure "No '$($propertyName)' element found"
	}

	[string]$oldValue = $propertyNode.InnerText
	If ($oldValue -Ne $newValue) {
		If ([string]::IsNullOrEmpty($oldValue)) {
			Log Warning "Old '$($propertyName)' value not present. It will not be replaced in additional places in the file." -indentLevel 1
		} Else {
			$wordReplacements.Add(@{ "oldValue" = $oldValue; "newValue" = $newValue; "property" = $propertyName }) | Out-Null
		}

		$propertyNode.InnerText = $newValue
		Log Success "[$($propertyName)] updated to '$($newValue)'" -indentLevel 1
	} Else {
		Log Success "[$($propertyName)] already is '$($newValue)'" -indentLevel 1
	}
}

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

	[System.Xml.XmlElement]$targetProvisionedServiceInfo = $targetProvisionedServiceInfos |
		Where-Object { $_.Name -IEq $serverName } |
		Select-Object -First 1
	If ($Null -Eq $targetProvisionedServiceInfo) {
		ScriptFailure "No info found for $($serviceDebugInfo) in [$($provisionedServicesPath)]"
	}

	Log Info "Processing $($serviceDebugInfo)"
	UpdateXmlValue -element $serverConnectionInfo -propertyName SubscriptionId -newValue $targetProvisionedServiceInfo.SubscriptionId
	UpdateXmlValue -element $serverConnectionInfo -propertyName UserName -newValue $targetProvisionedServiceInfo.Username
	UpdateXmlValue -element $serverConnectionInfo -propertyName Password -newValue $targetProvisionedServiceInfo.Password
}

LogNewLine
$environmentXml.Save($environmentFilePath)
Log Info "XML processing complete for [$($environmentFilePath)]"

If ($wordReplacements.Count -Gt 0) {
	LogNewLine
}

[UInt16]$replacementsSkipped = 0
ForEach ($replacement in $wordReplacements) {
	[string]$oldValueRegex = "\b$([System.Text.RegularExpressions.Regex]::Escape($replacement.oldValue))\b"
	[int]$matchCount = (Select-string -Path $environmentFilePath -Pattern $oldValueRegex).Count
	If ($matchCount -Eq 0) {
		Log Verbose "No more [$($replacement.property)] words with old value '$($replacement.oldValue)' found"
		continue
	}

	If (-Not (ConfirmAction "Replace $($matchCount) [$($replacement.property)] word(s) '$($replacement.oldValue)' with '$($replacement.newValue)'" -defaultYes)) {
		$replacementsSkipped += $matchCount
		continue
	}

	(Get-Content -Path $environmentFilePath) -replace $oldValueRegex,$replacement.newValue | Set-Content -Path $environmentFilePath
	Log Success "Replaced $($matchCount) [$($replacement.property)] word(s) '$($replacement.oldValue)'" -indentLevel 1
}

If ($replacementsSkipped -Gt 0) {
	Log Warning "Left $($replacementsSkipped) word(s) with old value(s) in [$($environmentFilePath)]"
}

LogNewLine
Log Info "Updated environment XML file [$($environmentFilePath)]"
