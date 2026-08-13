# UIレイアウト: フォームと各コントロールの生成のみ。イベント配線は EventHandlers.ps1 側で行う。

$form = New-Object System.Windows.Forms.Form
$form.Text = "LogAnalysisTool $SCRIPT_VERSION (FF14 Special Edition)"
$form.Size = New-Object System.Drawing.Size(1000, 600)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)

$ancTopRight = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Right
$ancTopLeftRight = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$ancAll = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

$txtFolder = New-Object System.Windows.Forms.TextBox
$txtFolder.Location = New-Object System.Drawing.Point(10, 10)
$txtFolder.Size = New-Object System.Drawing.Size(850, 25)
$txtFolder.Anchor = $ancTopLeftRight

$btnFolder = New-Object System.Windows.Forms.Button
$btnFolder.Text = "参照"
$btnFolder.Location = New-Object System.Drawing.Point(870, 10)
$btnFolder.Size = New-Object System.Drawing.Size(100, 25)
$btnFolder.Anchor = $ancTopRight

$txtKeyword = New-Object System.Windows.Forms.TextBox
$txtKeyword.Location = New-Object System.Drawing.Point(10, 45)
$txtKeyword.Size = New-Object System.Drawing.Size(180, 25)

$chkFixGarbled = New-Object System.Windows.Forms.CheckBox
$chkFixGarbled.Text = "修復して表示"
$chkFixGarbled.Location = New-Object System.Drawing.Point(200, 47)
$chkFixGarbled.Size = New-Object System.Drawing.Size(95, 22)
$chkFixGarbled.Checked = $true

$chkFF14Mode = New-Object System.Windows.Forms.CheckBox
$chkFF14Mode.Text = "FF14ログ最適化"
$chkFF14Mode.Location = New-Object System.Drawing.Point(300, 47)
$chkFF14Mode.Size = New-Object System.Drawing.Size(110, 22)
$chkFF14Mode.Checked = $true

$btnSearch = New-Object System.Windows.Forms.Button
$btnSearch.Text = "検索"
$btnSearch.Location = New-Object System.Drawing.Point(420, 45)
$btnSearch.Size = New-Object System.Drawing.Size(80, 25)

$btnReset = New-Object System.Windows.Forms.Button
$btnReset.Text = "リセット"
$btnReset.Location = New-Object System.Drawing.Point(510, 45)
$btnReset.Size = New-Object System.Drawing.Size(80, 25)

$btnExport = New-Object System.Windows.Forms.Button
$btnExport.Text = "保存"
$btnExport.Location = New-Object System.Drawing.Point(600, 45)
$btnExport.Size = New-Object System.Drawing.Size(80, 25)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Location = New-Object System.Drawing.Point(690, 50)
$lblStatus.Size = New-Object System.Drawing.Size(280, 20)
$lblStatus.Anchor = $ancTopLeftRight
$lblStatus.Text = "待機中 ($SCRIPT_VERSION)"

# --- ListView の生成とレイアウト設定 ---
$listView = New-Object System.Windows.Forms.ListView
$listView.Location = New-Object System.Drawing.Point(10, 80)
$listView.Size = New-Object System.Drawing.Size(960, 360)
$listView.View = "Details"
$listView.FullRowSelect = $true
$listView.Anchor = $ancAll

$listView.VirtualMode = $true
$doubleBufferProp = [System.Windows.Forms.Control].GetProperty("DoubleBuffered", [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::NonPublic)
$doubleBufferProp.SetValue($listView, $true, $null)

# カラム構成 (3つ)
$listView.Columns.Add("ファイル", 80) | Out-Null
$listView.Columns.Add("行番号", 50) | Out-Null
$listView.Columns.Add("内容", 1800) | Out-Null

# --- 下部 HEX インスペクターパネル ---
$lblHexTitle = New-Object System.Windows.Forms.Label
$lblHexTitle.Text = "選択行の生バイト (HEX):"
$lblHexTitle.Location = New-Object System.Drawing.Point(10, 450)
$lblHexTitle.Size = New-Object System.Drawing.Size(200, 20)
$lblHexTitle.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left

$txtHexInspector = New-Object System.Windows.Forms.TextBox
$txtHexInspector.Location = New-Object System.Drawing.Point(10, 470)
$txtHexInspector.Size = New-Object System.Drawing.Size(960, 80)
$txtHexInspector.Multiline = $true
$txtHexInspector.ReadOnly = $true
$txtHexInspector.ScrollBars = "Vertical"
$txtHexInspector.Anchor = [System.Windows.Forms.AnchorStyles]::Bottom -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right

# コンテキストメニュー(右クリックメニュー)の器だけここで用意する。項目の追加とクリック時の
# 挙動は EventHandlers.ps1 側(コピー処理と一緒)にまとめてある。
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuCopyRow = New-Object System.Windows.Forms.ToolStripMenuItem("行全体をコピー (&C)")
$menuCopyText = New-Object System.Windows.Forms.ToolStripMenuItem("内容（テキスト）のみコピー (&T)")
$contextMenu.Items.Add($menuCopyRow) | Out-Null
$contextMenu.Items.Add($menuCopyText) | Out-Null
$listView.ContextMenuStrip = $contextMenu

# コントロールの追加
$form.Controls.AddRange(@(
    $txtFolder, $btnFolder, $txtKeyword, $chkFixGarbled, $chkFF14Mode,
    $btnSearch, $btnReset, $btnExport, $lblStatus, $listView,
    $lblHexTitle, $txtHexInspector
  ))
