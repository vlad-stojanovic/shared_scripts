[CmdletBinding()]
Param(
	[Parameter(Mandatory=$False, HelpMessage="Process name to send keys to e.g. 'devenv' for Microsoft Visual Studio")]
	[ValidateNotNullOrEmpty()]
	[string]$processName = "devenv",

	[Parameter(Mandatory=$False, HelpMessage="Window title infix of the process  name to send keys to e.g. 'MyProject' when opening MyProject.csproj")]
	[string]$windowTitleInfix = "",

	[Parameter(Mandatory=$False, HelpMessage="Number of key iterations (entries to be processed in the Build Configuration)")]
	[int]$keyIterations = 50)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

If (-Not (ConfirmAction "Did you open Build configuration in Visual Studio and selected/highlighted the first 'Build' checkbox" -defaultYes)) {
	ScriptFailure "Please perform the necessary steps first"
}

# https://docs.microsoft.com/windows/win32/inputdev/virtual-key-codes
[UInt16[]]$keyCodes = @(
	, 0x20	# 1) Disable build (SPACE)
	, 0x27	# 2) Go (RIGHT)
	, 0x20	# 3) Disable deployment (SPACE)
	, 0x25	# 4) Go back (LEFT) to the starting point
	, 0x28	# 5) Move (DOWN) for next project build
)

& "$($PSScriptRoot)/send_inputs_to_window.ps1" `
	-processName $processName `
	-targetWindowTitle "Configuration Manager" `
	-targetWindowDescription "Build Configuration" `
	-mainProcessWindowTitleInfix $windowTitleInfix `
	-keyCodes $keyCodes `
	-keyIterations $keyIterations
