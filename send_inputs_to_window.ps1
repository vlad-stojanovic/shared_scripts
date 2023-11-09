[CmdletBinding()]
Param(
	[Parameter(Mandatory=$True, HelpMessage="Process name to send keys to e.g. 'devenv' for Microsoft Visual Studio")]
	[ValidateNotNullOrEmpty()]
	[string]$processName,

	[Parameter(Mandatory=$True, HelpMessage="Title of the target window to send keys to")]
	[ValidateNotNullOrEmpty()]
	[string]$targetWindowTitle,

	[Parameter(Mandatory=$True, HelpMessage="Description of the target window")]
	[ValidateNotNullOrEmpty()]
	[string]$targetWindowDescription,

	[Parameter(Mandatory=$False, HelpMessage="Main process window title infix")]
	[AllowNull()]
	[string]$mainProcessWindowTitleInfix = "",

	[Parameter(Mandatory=$True, HelpMessage="Virtual key codes (raw values) to send to the target window. See https://docs.microsoft.com/windows/win32/inputdev/virtual-key-codes")]
	[UInt16[]]$keyCodes,

	[Parameter(Mandatory=$False, HelpMessage="Number of times to repeat sending the provided key codes within a single cycle")]
	[UInt16]$keyIterations = 1,

	[Parameter(Mandatory=$False, HelpMessage="Number of seconds to wait between cycles are repeated. If the value is less than or equal to zero then do no repeats")]
	[Int32]$repeatCycleWaitTimeS = 0)

# Include common helper functions
. "$($PSScriptRoot)/common/_common.ps1"

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

		// https://docs.microsoft.com/windows/win32/inputdev/virtual-key-codes
		enum VirtualKeyCodes {
			VK_LEFT = 0x25,
			VK_UP = 0x26,
			VK_RIGHT = 0x27,
			VK_DOWN = 0x28,
			VK_SPACE = 0x20,
			VK_TAB = 0x09,
			VK_RETURN = 0x0D,
			VK_LBUTTON = 0x01,
			VK_RBUTTON = 0x02,
		}

		class EnumWindowParams
		{
			public List<IntPtr> WindowList { get; private set; }
			public string TargetWindowTitle { get; private set; }

			public EnumWindowParams(string targetWindowTitle)
			{
				WindowList = new List<IntPtr>();
				TargetWindowTitle = targetWindowTitle.Trim();
			}
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

		public static bool SetForegroundWindowWrapper(IntPtr processHandle)
		{
			if (processHandle == GetForegroundWindowWrapper())
			{
				// Requested window is already in the foreground.
				return true;
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

		public static int SendInputsToTargetWindow(IntPtr processHandle, ushort[] keyCodesRaw, int keyIterations)
		{
			List<Input> inputList = new List<Input>();
			foreach (var code in keyCodesRaw)
			{
				inputList.AddRange(GenerateKeyboardInput(code));
			}

			for (int i = 0; i < keyIterations; i++)
			{
				if (processHandle != GetForegroundWindowWrapper())
				{
					return i;
				}

				if (!SendInputWrapper(inputList.ToArray()))
				{
					return i;
				}
			}

			return keyIterations;
		}

		private static bool EnumWindow(IntPtr handle, IntPtr pointer)
		{
			GCHandle gch = GCHandle.FromIntPtr(pointer);
			EnumWindowParams gchParams = gch.Target as EnumWindowParams;
			if (gchParams == null)
			{
				throw new InvalidCastException("GCHandle Target could not be cast correctly");
			}

			List<IntPtr> list = gchParams.WindowList;
			string targetWindowTitle = gchParams.TargetWindowTitle;
			if (list == null || string.IsNullOrEmpty(targetWindowTitle))
			{
				throw new InvalidCastException("GCHandle Target has invalid fields");
			}

			int length = GetWindowTextLength(handle);
			if (length <= 0)
			{
				// Continue with the search
				return true;
			}

			StringBuilder sb = new StringBuilder(length + 1);
			GetWindowText(handle, sb, sb.Capacity);
			string windowTitle = sb.ToString().Trim();
			if (windowTitle == targetWindowTitle)
			{
				list.Add(handle);

				// Stop further execution
				return false;
			}

			// Continue with the search
			return true;
		}

		public static long[] FindTargetWindowForThreadId(int threadId, string targetWindowTitle)
		{
			EnumWindowParams ewParams = new EnumWindowParams(targetWindowTitle);
			GCHandle gcHandle = GCHandle.Alloc(ewParams);
			try
			{
				EnumThreadWindows((uint)threadId, new EnumWindowProc(EnumWindow), GCHandle.ToIntPtr(gcHandle));
			}
			finally
			{
				if (gcHandle.IsAllocated)
				{
					gcHandle.Free();
				}
			}

			if (ewParams.WindowList.Any())
			{
				return ewParams
					.WindowList
					.Select(handle => handle.ToInt64())
					.ToArray();
			}

			return null;
		}

		public static long[] FindTargetWindow(Process process, string targetWindowTitle)
		{
			long[] processResult = FindTargetWindowForThreadId(process.Id, targetWindowTitle);
			if (processResult != null && processResult.Any())
			{
				return processResult;
			}

			foreach (ProcessThread thread in process.Threads)
			{
				long[] threadResult = FindTargetWindowForThreadId(thread.Id, targetWindowTitle);
				if (threadResult != null && threadResult.Any())
				{
					return threadResult;
				}
			}

			return null;
		}
	}
}
"@

Add-Type -TypeDefinition $csSource -Language CSharp

While ($True) {
	[System.Diagnostics.Process[]]$processes = Get-Process -Name $processName -ErrorAction Ignore |
		Where-Object { [string]::IsNullOrEmpty($mainProcessWindowTitleInfix) -Or $_.MainWindowTitle.Contains($mainProcessWindowTitleInfix) }
	If ($processes.Count -Gt 1) {
		Log Warning "Found $($processes.Count) matching processes"
	}

	If ($processes.Count -Gt 0) {
		[int]$targetWindowsProcessed = 0
		ForEach ($process in $processes) {
			[string]$processInfo = "#$($process.Id) [$($processName)] window handle [$($process.MainWindowHandle)] title [$($process.MainWindowTitle)]"
			[string[]]$processLogEntries = @($processInfo)
			[long[]]$targetWindowHandles = [VStojanovic.UICommands.PSWrapper]::FindTargetWindow($process, $targetWindowTitle);
			If ($targetWindowHandles.Count -Eq 0) {
				Log Warning "Could not find $($targetWindowDescription) window open within" -additionalEntries $processLogEntries
				continue
			}

			If ($targetWindowHandles.Count -Gt 1) {
				Log Warning "Found $($targetWindowHandles.Count) $($targetWindowDescription) windows within" -additionalEntries $processLogEntries
			}

			ForEach ($targetWindowHandle in $targetWindowHandles) {
				[bool]$result = [VStojanovic.UICommands.PSWrapper]::SetForegroundWindowWrapper($targetWindowHandle)
				$result = [VStojanovic.UICommands.PSWrapper]::ShowWindowWrapper($targetWindowHandle, 5)

				[string]$windowLogEntries = @("$($processInfo) -> #$($targetWindowHandle)")
				[int]$keyIterationsSent = [VStojanovic.UICommands.PSWrapper]::SendInputsToTargetWindow($targetWindowHandle, $keyCodes, $keyIterations);
				If ($keyIterations -Eq $keyIterationsSent) {
					Log Success "Sent $($keyIterations) key command(s) to" -additionalEntries $windowLogEntries
					$targetWindowsProcessed++
				} ElseIf ($keyIterationsSent -Gt 0) {
					Log Warning "Sent $($keyIterationsSent)/$($keyIterations) key command(s) to" -additionalEntries $windowLogEntries
				} Else {
					Log Error "Failed to send key command(s) to" -additionalEntries $windowLogEntries
				}
			}
		}

		If ($targetWindowsProcessed -Eq 0) {
			Log Warning "No $($targetWindowDescription) windows processed in $($processes.Count) [$($processName)] process(es)"
		} Else {
			Log Warning "Check manually that the $($targetWindowsProcessed) window(s) have been processed correctly"
		}
	} Else {
		Log Warning "Did not find any matching processes [$($processName)]. Add correct filters for process name and window title"
	}

	If ($repeatCycleWaitTimeS -Gt 0) {
		Log Verbose "Waiting for $($repeatCycleWaitTimeS)s before another cycle..."
		LogNewLine
		Start-Sleep -Seconds $repeatCycleWaitTimeS
	} Else {
		break
	}
}
