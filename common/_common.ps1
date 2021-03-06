# File includes common helper functions that may exit the calling scope (e.g. in case of failures)
# and are therefore not safe to be used in (alias) functions, but only in scripts.

# Include common safe helper functions
. "$($PSScriptRoot)/_common_safe.ps1"

function ScriptExit() {
	[OutputType([System.Void])]
	Param (
		[Parameter(Mandatory=$True)]
		[Int]$exitStatus,

		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$message)

	[string]$logFileMessage = $Null
	[string]$logType = $Null
	If ($exitStatus -Eq 0) {
		$logType = "Success"
		$logFileMessage = "SCRIPT COMPLETED SUCCESSFULLY"
	} Else {
		$logType = "Error"
		$logFileMessage = "SCRIPT FAILED WITH STATUS $($exitStatus)"
	}

	Log -type $logType -message $message

	# Add a new line to the log file to make script exit more readable.
	PersistMessage -directoryName "script_execution" -message "$($logFileMessage)`n- - -`n"
	exit $exitStatus
}

function ScriptFailure() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$message)
	ScriptExit -exitStatus 1 -message $message
}

function ScriptSuccess() {
	[OutputType([System.Void])]
	Param(
		[Parameter(Mandatory=$True)]
		[ValidateNotNullOrEmpty()]
		[string]$message)
	ScriptExit -exitStatus 0 -message $message
}
