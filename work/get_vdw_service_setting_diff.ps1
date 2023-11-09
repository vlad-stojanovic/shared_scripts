Param(
	[Parameter(Mandatory=$True, HelpMessage="Path to OLD service settings XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$serviceSettingsOldXmlPath,

	[Parameter(Mandatory=$True, HelpMessage="Path to NEW service settings XML file")]
	[ValidateNotNullOrEmpty()]
	[string]$serviceSettingsNewXmlPath,

	[Parameter(Mandatory=$False, HelpMessage="Updated/'NEW' branch name (with more commits than the base branch e.g. master/main)")]
	[ValidateNotNullOrEmpty()]
	[string]$newRemoteBranchName = "origin/master",

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

# We might support multiple app types (as input script parameters),
# for now pass a single app type but internally treat the value as part of the collection.
[string[]]$vdwAppTypes = @($vdwAppType)

function validate_hash_table() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="HashTable to validate")]
		[AllowNull()]
		[HashTable]$hashTable,

		[Parameter(Mandatory=$True, HelpMessage="Error message to print if the HashTable is invalid")]
		[ValidateNotNullOrEmpty()]
		[string]$errorMessage)
	If ($Null -Eq $hashTable) {
		If ($showDebugLogs.IsPresent) { Log Error "[NULL]$($errorMessage)" }
		return $False
	} ElseIf ($hashTable.Keys.Count -Eq 0) {
		If ($showDebugLogs.IsPresent) { Log Error "[EMPTY]$($errorMessage)" }
		return $False
	}

	return $True
}

function validate_hash_tables() {
	[OutputType([bool])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Old HashTable to validate")]
		[AllowNull()]
		[HashTable]$oldHashTable,

		[Parameter(Mandatory=$True, HelpMessage="New HashTable to validate")]
		[AllowNull()]
		[HashTable]$newHashTable,

		[Parameter(Mandatory=$True, HelpMessage="Error message to print if one of the HashTable elements is invalid")]
		[ValidateNotNullOrEmpty()]
		[string]$errorMessage)
	[bool]$validOld = validate_hash_table -hashTable $oldHashTable -errorMessage "[OLD] $($errorMessage)"
	[bool]$validNew = validate_hash_table -hashTable $newHashTable -errorMessage "[NEW] $($errorMessage)"
	return ($validOld -And $validNew)
}

function get_service_settings() {
	[OutputType([HashTable])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="Path to service settings XML file")]
		[ValidateNotNullOrEmpty()]
		[string]$serviceSettingsXmlPath)

	function get_vdw_app_type_value() {
		[OutputType([HashTable])]
		Param(
			[Parameter(Mandatory=$True, HelpMessage="Feature switch element")]
			[ValidateNotNullOrEmpty()]
			[System.Xml.XmlElement]$element,

			[Parameter(Mandatory=$True, HelpMessage="VDW app type name")]
			[ValidateNotNullOrEmpty()]
			[string]$vdwAppTypeName)
		[string]$type = "base"
		[string]$value = $element.Value
		[string]$vdwAppTypeBaseName = "$($vdwAppTypeName).Base"
		If (-Not [string]::IsNullOrEmpty($element[$vdwAppTypeName].Value)) {
			$type = $vdwAppTypeName
			$value = $element[$vdwAppTypeName].Value
		} ElseIf (-Not [string]::IsNullOrEmpty($element[$vdwAppTypeBaseName].Value)) {
			$type = $vdwAppTypeBaseName
			$value = $element[$vdwAppTypeBaseName].Value
		}

		return @{ type = $type; value = $value.ToUpper(); retired = $element.retired; }
	}

	If (-Not (Test-Path -Path $serviceSettingsXmlPath -pathType Leaf)) {
		Log Error "Service settings XML path invalid [$($serviceSettingsXmlPath)]"
		return $Null
	}

	[System.Xml.XmlElement[]]$featureSwitchesElements = ([Xml](Get-Content -Path $serviceSettingsXmlPath)) |
		Select-Object -ExpandProperty "ServiceSettings" |
		Select-Object -ExpandProperty "FeatureSwitches"
	If ($featureSwitchesElements.Count -Gt 1) {
		Log Error "Found $($featureSwitchesElements.Count) feature switches elements in [$($serviceSettingsXmlPath)]"
		return $Null
	}
	
	[System.Xml.XmlElement]$featureSwitchesElement = $featureSwitchesElements[0]
	If ($Null -Eq $featureSwitchesElement) {
		Log Error "Feature switches element not found in [$($serviceSettingsXmlPath)]"
		return $Null
	}

	[HashTable]$fsMap = @{}
	$featureSwitchesElement |
		Select-Object -ExpandProperty "FeatureSwitch" |
		ForEach-Object {
			[HashTable]$fsAppTypeMap = @{}
			[System.Xml.XmlElement]$fsElement = $_
			ForEach ($appType in $vdwAppTypes) {
				$fsAppTypeMap[$appType] = get_vdw_app_type_value -element $fsElement -vdwAppTypeName $appType
			}

			$fsMap[$fsElement.name] = $fsAppTypeMap
		}

	return $fsMap
}

function get_fs_description() {
	[OutputType([string])]
	Param(
		[Parameter(Mandatory=$True, HelpMessage="FS HashTable to describe (e.g. for logging)")]
		[ValidateNotNull()]
		[HashTable]$fsHashTable,

		[Parameter(Mandatory=$True, HelpMessage="Description prefix")]
		[ValidateNotNullOrEmpty()]
		[string]$prefix)
	[string]$description = "$($prefix): $($fsHashTable.value) ($($fsHashTable.type))"
	If ($fsHashTable.retired -IEq "true") {
		$description = "$($description) RETIRED"
	}

	return $description
}

[HashTable]$oldFsMap = get_service_settings -serviceSettingsXmlPath $serviceSettingsOldXmlPath
[HashTable]$newFsMap = get_service_settings -serviceSettingsXmlPath $serviceSettingsNewXmlPath
If (-Not (validate_hash_tables -oldHashTable $oldFsMap -newHashTable $newFsMap -errorMessage "FS map not found in service settings")) {
	return
}

[Int]$totalFs = 0
[Int]$errorFs = 0
[Int]$newFs = 0
[Int]$mismatchFs = 0
Log Success "Found $($newFsMap.Keys.Count) feature switch(es)"

ForEach ($fsName in ($newFsMap.Keys | Sort-Object)) {
	$totalFs++
	[HashTable]$oldFsValues = $oldFsMap[$fsName]
	[HashTable]$newFsValues = $newFsMap[$fsName]
	If (-Not (validate_hash_tables -oldHashTable $oldFsValues -newHashTable $newFsValues -errorMessage "FS '$($fsName)' not found in service settings")) {
		If ($newFsValues.Count -Gt 0) {
			$newFs++

			# Don't treat as an error if there is no FS in the old settings,
			# but it is present in the new settings.
			If ($showNewSettings.IsPresent) {
				Log Warning "FS '$($fsName)' found only in new service settings" `
					-additionalEntries ($vdwAppTypes |
						ForEach-Object {
							[string]$appName = $_
							[HashTable]$fsAppValue = $newFsValues[$appName]
							return (get_fs_description -prefix $appName -fsHashTable $fsAppValue)
						}) `
					-entryPrefix "- "
			}
		} Else {
			$errorFs++
		}

		continue
	}

	[bool]$isMismatch = $False
	ForEach ($vdwAppType in $vdwAppTypes) {
		[HashTable]$oldFsAppValue = $oldFsValues[$vdwAppType]
		[HashTable]$newFsAppValue = $newFsValues[$vdwAppType]
		If (-Not (validate_hash_tables -oldHashTable $oldFsAppValue -newHashTable $newFsAppValue -errorMessage "AppType '$($vdwAppType)' value not found for FS '$($fsName)'")) {
			# This should not happen - it would imply an error in populating the helper HashTables in the logic above
			$errorFs++
			continue
		}

		If ($oldFsAppValue.value -IEq $newFsAppValue.value) {
			continue
		}

		$isMismatch = $True

		# Log different colors - green for FS turned ON, yellow for FS turned OFF.
		[string]$logType = "Warning"
		[string]$explanation = "turned OFF"
		If ($newFsAppValue.value -IEq "ON") {
			$logType = "Success"
			$explanation = "turned ON"
		}

		Log $logType "AppType '$($vdwAppType)' $($explanation) '$($fsName)'" `
			-additionalEntries @(
				, (get_fs_description -prefix "OLD" -fsHashTable $oldFsAppValue)
				, (get_fs_description -prefix "NEW" -fsHashTable $newFsAppValue)) `
			-entryPrefix "- "
		If ($showUpdateDetails.IsPresent) {
			[Microsoft.PowerShell.Commands.MatchInfo]$match = Select-String -Path $serviceSettingsNewXmlPath -Pattern "<FeatureSwitch\b.*\b$($fsName)\b" -Context 0,30
			If ($Null -Eq $match) {
				continue
			}

			[Int]$startLine = $match | Select-Object -ExpandProperty LineNumber
			[Int]$offset = 10 # Default offset for FS definition block
			[string[]]$nextLines = $match.Context.PostContext
			For ([Int]$i = 0; $i -Lt $nextLines.Count; $i++) {
				If ($nextLines[$i] -imatch "</FeatureSwitch>") {
					$offset = $i + 1;
					break;
				}
			}

			[string]$afterDate = (Get-Date).AddMonths(-3).ToString("yyyy-MM-dd") # Look only three monthts in the past, for slight optimization
			[string]$gitCmd = "git log $($newRemoteBranchName) -L $($startLine),$($startLine + $offset):Sql\xdb\manifest\svc\sql\manifest\ServiceSettings_SQLServer_Common.xml --after=$($afterDate)"
			If (ConfirmAction "Execute command [$($gitCmd)]" -defaultYes) {
				Invoke-Expression -Command $gitCmd
				LogNewLine
			}
		}
	}

	If ($isMismatch) {
		$mismatchFs++
	}
}

LogNewLine
Log Verbose "Processed $($totalFs) feature switch(es)"

If ($errorFs -Gt 0) {
	Log Error "Failed to process $($errorFs) feature switch(es)"
}

If ($mismatchFs -Gt 0) {
	Log Warning "Mismatch found in $($mismatchFs) feature switch(es)"
}

If ($newFs -Gt 0) {
	Log Warning "Found $($newFs) new feature switch(es)"
}
