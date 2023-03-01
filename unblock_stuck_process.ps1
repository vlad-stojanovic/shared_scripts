[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Image (process) name")]
	[ValidateNotNullOrEmpty()]
	[string]$processName,

	[Parameter(Mandatory=$False, HelpMessage="Sleep time between status checking cycles")]
	[int]$sleepTimeS = 5,

	[Parameter(Mandatory=$False, HelpMessage="Should we log every checking cycle")]
	[switch]$logEveryCycle,

	[Parameter(Mandatory=$False, HelpMessage="Method for getting processes")]
	[ValidateSet("CMD", "PowerShell")]
	[string]$method = "CMD")

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

Clear-Host
Log Info "Checking for [$($processName)] processes via $($method) every $($sleepTimeS) seconds..."
[string]$processNameExtension = [System.IO.Path]::GetExtension($processName)
If ($method -IEq "CMD") {
	If ([string]::IsNullOrEmpty($processNameExtension)) {
		Log Warning "CMD process names should have an extension, appending .exe"
		$processName = "$($processName).exe"
	}
} Else {
	If (-Not [string]::IsNullOrEmpty($processNameExtension)) {
		Log Warning "PowerShell process names should not have an extension, removing $($processNameExtension)"
		$processName = [System.IO.Path]::GetFileNameWithoutExtension($processName)
	}
}

While ($True) {
	[PSCustomObject[]]$allProcesses = $Null
	if ($method -IEq "CMD") {
		# Get-Process may not return correct process status. CMD's TASKLIST should work better.
		# Map the fields of interest 
		$allProcesses = cmd /C "TASKLIST /FI `"ImageName eq $($processName)`" /V /FO CSV" |
			ConvertFrom-Csv |
			ForEach-Object { @{ "Id" = $_.PID; "Responding" = $_.Status -IEq "Running"; "Status" = $_.Status; } }
	} Else {
		# Map the fields of interest
		$allProcesses = Get-Process -Name $processName -ErrorAction Ignore |
			ForEach-Object { 
				[string]$status = "Responding"
				If (-Not $_.Responding) {
					$status = "Not responding"
				}

				return @{ "Id" = $_.Id; "Responding" = $_.Responding; "Status" = $status; }
			}
	}

	If ($allProcesses.Count -Eq 0) {
		break
	}

	If ($logEveryCycle.IsPresent) {
		Log Verbose "Found $($allProcesses.Count) [$($processName)] process(es)"
	}

	$allProcesses |
		Where-Object { -Not $_.Responding } |
		ForEach-Object {
			Log Warning "Killing #$($_.Id) [$($processName)] with status '$($_.Status)'"
			Stop-Process -Id $_.Id -Force
		}

	Start-Sleep -Seconds $sleepTimeS
}

Log Success "Status checks complete, no more [$($processName)] processes found"
