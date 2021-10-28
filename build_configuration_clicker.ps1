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

# Example taken from: https://www.codeproject.com/Articles/5264831/How-to-Send-Inputs-using-Csharp
$csSource = @"
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace VStojanovic.UICommands
{
	[StructLayout(LayoutKind.Sequential)]
	public struct KeyboardInput
	{
		public ushort wVk;
		public ushort wScan;
		public uint dwFlags;
		public uint time;
		public IntPtr dwExtraInfo;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct MouseInput
	{
		public int dx;
		public int dy;
		public uint mouseData;
		public uint dwFlags;
		public uint time;
		public IntPtr dwExtraInfo;
	}

	[StructLayout(LayoutKind.Sequential)]
	public struct HardwareInput
	{
		public uint uMsg;
		public ushort wParamL;
		public ushort wParamH;
	}

	[StructLayout(LayoutKind.Explicit)]
	public struct InputUnion
	{
		[FieldOffset(0)] public MouseInput mi;
		[FieldOffset(0)] public KeyboardInput ki;
		[FieldOffset(0)] public HardwareInput hi;
	}

	public struct Input
	{
		public int type;
		public InputUnion u;
	}

	[Flags]
	public enum InputType
	{
		Mouse = 0,
		Keyboard = 1,
		Hardware = 2
	}

	[Flags]
	public enum KeyEventF
	{
		KeyDown = 0x0000,
		ExtendedKey = 0x0001,
		KeyUp = 0x0002,
		Unicode = 0x0004,
		Scancode = 0x0008
	}

	[Flags]
	public enum MouseEventF
	{
		Absolute = 0x8000,
		HWheel = 0x01000,
		Move = 0x0001,
		MoveNoCoalesce = 0x2000,
		LeftDown = 0x0002,
		LeftUp = 0x0004,
		RightDown = 0x0008,
		RightUp = 0x0010,
		MiddleDown = 0x0020,
		MiddleUp = 0x0040,
		VirtualDesk = 0x4000,
		Wheel = 0x0800,
		XDown = 0x0080,
		XUp = 0x0100
	}

	public static class PSWrapper
	{
		[DllImport("user32.dll", SetLastError = true)]
		private static extern uint SendInput(uint nInputs, Input[] pInputs, int cbSize);

		[DllImport("user32.dll")]
		private static extern IntPtr GetMessageExtraInfo();

		[DllImport("user32.dll")]
		static extern IntPtr GetForegroundWindow();

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool SetForegroundWindow(IntPtr hWnd);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

		public delegate bool EnumWindowProc(IntPtr hwnd, IntPtr lParam);

		[DllImport("user32.dll")]
		[return: MarshalAs(UnmanagedType.Bool)]
		public static extern bool EnumThreadWindows(uint dwThreadId, EnumWindowProc lpEnumFunc, IntPtr lParam);

		[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
		static extern int GetWindowTextLength(IntPtr hWnd);

		[DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

		public static int WindowWaitTimeMs = 40;
		public static int InputWaitTimeMs = 25;

		public static string BuildConfigurationManagerWindowTitle = "Configuration Manager";

		// https://docs.microsoft.com/windows/win32/inputdev/virtual-key-codes
		enum VirtualKeyCodes {
			VK_LEFT = 0x25,
			VK_UP = 0x26,
			VK_RIGHT = 0x27,
			VK_DOWN = 0x28,
			VK_SPACE = 0x20,
			VK_RETURN = 0x0D,
			VK_LBUTTON = 0x01,
			VK_RBUTTON = 0x02,
		}

		public static Input[] GenerateMouseClickInput(int dx, int dy)
		{
			return new Input[]
			{
				new Input
				{
					type = (int)InputType.Mouse,
					u = new InputUnion
					{
						mi = new MouseInput
						{
							dx = dx,
							dy = dy,
							dwFlags = (uint)(MouseEventF.Move | MouseEventF.LeftDown),
							dwExtraInfo = GetMessageExtraInfo()
						}
					}
				},
				new Input
				{
					type = (int)InputType.Mouse,
					u = new InputUnion
					{
						mi = new MouseInput
						{
							dwFlags = (uint)(MouseEventF.LeftUp),
							dwExtraInfo = GetMessageExtraInfo()
						}
					}
				}
			};
		}

		public static Input[] GenerateKeyboardInput(ushort virtualKeyCode)
		{
			return new Input[]
			{
				new Input
				{
					type = (int)InputType.Keyboard,
					u = new InputUnion
					{
						ki = new KeyboardInput
						{
							wVk = virtualKeyCode,
							wScan = 0,
							dwFlags = (uint)KeyEventF.KeyDown,
							dwExtraInfo = GetMessageExtraInfo()
						}
					}
				},
				new Input
				{
					type = (int)InputType.Keyboard,
					u = new InputUnion
					{
						ki = new KeyboardInput
						{
							wVk = virtualKeyCode,
							wScan = 0,
							dwFlags = (uint)KeyEventF.KeyUp,
							dwExtraInfo = GetMessageExtraInfo()
						}
					}
				}
			};
		}

		public static bool SendInputWrapper(Input[] inputs)
		{
			// https://docs.microsoft.com/windows/win32/api/winuser/nf-winuser-sendinput
			uint inputCount = (uint)inputs.Length;
			
			if (inputCount != SendInput(inputCount, inputs, Marshal.SizeOf(typeof(Input))))
			{
				return false;
			}

			// Give some time for processing the mouse commands
			Thread.Sleep(InputWaitTimeMs);
			return true;
		}

		public static IntPtr GetForegroundWindowWrapper()
		{
			// https://docs.microsoft.com/windows/win32/api/winuser/nf-winuser-getforegroundwindow
			return GetForegroundWindow();
		}

		public static bool? SetForegroundWindowWrapper(IntPtr processHandle)
		{
			if (processHandle == GetForegroundWindowWrapper())
			{
				return null;
			}

			// https://docs.microsoft.com/windows/win32/api/winuser/nf-winuser-setforegroundwindow
			if (!SetForegroundWindow(processHandle))
			{
				return false;
			}

			// Give some time for processing the window commands
			Thread.Sleep(WindowWaitTimeMs);
			return true;
		}

		public static bool ShowWindowWrapper(IntPtr processHandle, int showType)
		{
			// https://docs.microsoft.com/windows/win32/api/winuser/nf-winuser-showwindow
			bool result = ShowWindow(processHandle, showType);

			// Give some time for processing the window commands
			Thread.Sleep(WindowWaitTimeMs);
			return result;
		}

		public static bool SendBuildConfigurationInputs(IntPtr processHandle, int keyIterations)
		{
			List<Input> inputList = new List<Input>();

			VirtualKeyCodes[] keyCodes =
			{
				VirtualKeyCodes.VK_SPACE,	// 1) Disable build (SPACE)
				VirtualKeyCodes.VK_RIGHT,	// 2) Go (RIGHT)
				VirtualKeyCodes.VK_SPACE,	// 3) Disable deployment (SPACE)
				VirtualKeyCodes.VK_LEFT,	// 4) Go back (LEFT) to the starting point
				VirtualKeyCodes.VK_DOWN		// 5) Move (DOWN) for next project build
			};

			foreach (var code in keyCodes)
			{
				inputList.AddRange(GenerateKeyboardInput((ushort)code));
			}

			for (int i = 0; i < keyIterations; i++)
			{
				if (processHandle != GetForegroundWindowWrapper())
				{
					return false;
				}

				if (!SendInputWrapper(inputList.ToArray()))
				{
					return false;
				}
			}

			return true;
		}

		private static bool EnumWindow(IntPtr handle, IntPtr pointer)
		{
			GCHandle gch = GCHandle.FromIntPtr(pointer);
			List<IntPtr> list = gch.Target as List<IntPtr>;
			if (list == null)
			{
				throw new InvalidCastException("GCHandle Target could not be cast as List<IntPtr>");
			}

			int length = GetWindowTextLength(handle);
			if (length <= 0)
			{
				// Continue with the search
				return true;
			}

			StringBuilder sb = new StringBuilder(length + 1);
			GetWindowText(handle, sb, sb.Capacity);
			string windowTitle = sb.ToString();
			if (windowTitle == BuildConfigurationManagerWindowTitle)
			{
				list.Add(handle);

				// Stop further execution
				return false;
			}

			// Continue with the search
			return true;
		}

		public static long FindBuildConfigurationWindowForThreadId(int threadId)
		{
			List<IntPtr> resultList = new List<IntPtr>();

			GCHandle listHandle = GCHandle.Alloc(resultList);
			try
			{
				EnumThreadWindows((uint)threadId, new EnumWindowProc(EnumWindow), GCHandle.ToIntPtr(listHandle));
			}
			finally
			{
				if (listHandle.IsAllocated)
				{
					listHandle.Free();
				}
			}

			if (resultList.Count > 0)
			{
				return resultList[0].ToInt64();
			}

			return 0L;
		}

		public static long FindBuildConfigurationWindow(Process process)
		{
			long processResult = FindBuildConfigurationWindowForThreadId(process.Id);
			if (processResult != 0)
			{
				return processResult;
			}

			foreach (ProcessThread thread in process.Threads)
			{
				long threadResult = FindBuildConfigurationWindowForThreadId(thread.Id);
				if (threadResult != 0)
				{
					return threadResult;
				}
			}

			return 0L;
		}
	}
}
"@

Add-Type -ReferencedAssemblies @() -TypeDefinition $csSource -Language CSharp

[System.Diagnostics.Process[]]$processes = Get-Process -Name $processName | `
	Where-Object { $_.MainWindowTitle.Contains($windowTitleInfix) }
If ($processes.Count -Gt 1) {
	LogWarning "Found $($processes.Count) matching processes"
} ElseIf ($processes.Count -Eq 0) {
	ScriptFailure "Did not find any matching processes [$($processName)]. Add correct filters for process name and window title"
}

[int]$buildConfigurationsProcessed = 0
ForEach ($process in $processes) {
	[string]$processInfo = "#$($process.Id) [$($processName)] window handle [$($process.MainWindowHandle)] title [$($process.MainWindowTitle)]"
	[long]$buildConfigurationWindowHandle = [VStojanovic.UICommands.PSWrapper]::FindBuildConfigurationWindow($process);
	If ($buildConfigurationWindowHandle -Eq 0) {
		LogWarning "Could not find Build Configuration window open within`n`t$($processInfo)"
		continue
	}

	[bool]$result = [VStojanovic.UICommands.PSWrapper]::SetForegroundWindowWrapper($buildConfigurationWindowHandle)
	$result = [VStojanovic.UICommands.PSWrapper]::ShowWindowWrapper($buildConfigurationWindowHandle, 5)

	$result = [VStojanovic.UICommands.PSWrapper]::SendBuildConfigurationInputs($buildConfigurationWindowHandle, $keyIterations);
	If ($result) {
		LogSuccess "Sent $($keyIterations) key commands to`n`t$($processInfo) -> #$($buildConfigurationWindowHandle)"
		$buildConfigurationsProcessed++
	} Else {
		LogError "Failed to send key commands to`n`t$($processInfo) -> #$($buildConfigurationWindowHandle)"
	}
}

If ($buildConfigurationsProcessed -Eq 0) {
	ScriptFailure "No build configuration windows processed in $($processes.Count) [$($processName)] process(es)"
}

LogWarning "Check manually that the build configuration is now correct (e.g. a single current project is being built)"