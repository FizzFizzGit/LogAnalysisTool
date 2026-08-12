# Win32 API定義: コンソール非表示 / WM_SETREDRAWによる再描画抑制

$asyncCode = @'
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern int SendMessage(IntPtr hWnd, int wMsg, int wParam, int lParam);
'@
$type = Add-Type -MemberDefinition $asyncCode -Name "Win32ShowWindow" -Namespace "Win32Functions" -PassThru

$hwnd = $type::GetConsoleWindow()
if ($hwnd -ne [IntPtr]::Zero) {
  $type::ShowWindow($hwnd, 0) | Out-Null
}

$WM_SETREDRAW = 0x000B

function Suspend-Drawing ($ctrl) {
  $type::SendMessage($ctrl.Handle, $WM_SETREDRAW, 0, 0) | Out-Null
}

function Resume-Drawing ($ctrl) {
  $type::SendMessage($ctrl.Handle, $WM_SETREDRAW, 1, 0) | Out-Null
  $ctrl.Invalidate()
}
