# --- コンソールウィンドウを非表示にするWin32 API定義 ---
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

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SCRIPT_VERSION = "v1.3.3"

$form = New-Object System.Windows.Forms.Form
$form.Text = "ログ検索ツール $SCRIPT_VERSION (FF14 Special Edition)"
$form.Size = New-Object System.Drawing.Size(1000, 600)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)

$script:psInstance = $null
$script:asyncResult = $null
$script:timer = $null
$script:resultQueue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
$script:resultList = [System.Collections.Generic.List[PSObject]]::new()
$script:isUpdatingUI = $false
$script:searchState = "Stopped"
$script:pauseEvent = $null

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
$listView.Columns.Add("ファイル", 150) | Out-Null
$listView.Columns.Add("行番号", 80) | Out-Null
$listView.Columns.Add("内容", 710) | Out-Null

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

# コントロールの追加
$form.Controls.AddRange(@(
    $txtFolder, $btnFolder, $txtKeyword, $chkFixGarbled, $chkFF14Mode,
    $btnSearch, $btnReset, $btnExport, $lblStatus, $listView,
    $lblHexTitle, $txtHexInspector
  ))

# 描画イベント
$listView.Add_RetrieveVirtualItem({
    param($sender, $e)
    if ($e.ItemIndex -lt $script:resultList.Count) {
      $data = $script:resultList[$e.ItemIndex]
      $item = New-Object System.Windows.Forms.ListViewItem([string]$data.FilePath)
      $item.SubItems.Add([string]$data.LineNo) | Out-Null
      $item.SubItems.Add([string]$data.Text) | Out-Null
      $e.Item = $item
    }
  })

# 行選択時のHEX表示処理
$listView.Add_SelectedIndexChanged({
    if ($listView.SelectedIndices.Count -gt 0) {
      $selectedIndex = $listView.SelectedIndices[0]
      if ($selectedIndex -lt $script:resultList.Count) {
        $txtHexInspector.Text = $script:resultList[$selectedIndex].Hex
      }
    } else {
      $txtHexInspector.Text = ""
    }
  })

$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuCopyRow = New-Object System.Windows.Forms.ToolStripMenuItem("行全体をコピー (&C)")
$menuCopyText = New-Object System.Windows.Forms.ToolStripMenuItem("内容（テキスト）のみコピー (&T)")
$contextMenu.Items.Add($menuCopyRow) | Out-Null
$contextMenu.Items.Add($menuCopyText) | Out-Null
$listView.ContextMenuStrip = $contextMenu

$script:CopySelectedItems = {
  param([bool]$textOnly = $false)
  if ($listView.SelectedIndices.Count -eq 0) {
    return
  }

  $sb = New-Object System.Text.StringBuilder
  foreach ($index in $listView.SelectedIndices) {
    if ($index -lt $script:resultList.Count) {
      $item = $script:resultList[$index]
      if ($textOnly) {
        [void]$sb.AppendLine([string]$item.Text)
      }
      else {
        [void]$sb.AppendLine("$($item.FilePath)`t$($item.LineNo)`t$($item.Text)`t$($item.Hex)")
      }
    }
  }
  if ($sb.Length -gt 0) {
    [System.Windows.Forms.Clipboard]::SetText($sb.ToString())
  }
}

$menuCopyRow.Add_Click({ & $script:CopySelectedItems $false })
$menuCopyText.Add_Click({ & $script:CopySelectedItems $true })

$btnExport.Add_Click({
    if ($script:resultList.Count -eq 0) {
      [System.Windows.Forms.MessageBox]::Show("出力する検索結果がありません。")
      return
    }

    $saveDlg = New-Object System.Windows.Forms.SaveFileDialog
    $saveDlg.Filter = "CSVファイル (*.csv)|*.csv|テキストファイル (*.txt)|*.txt"
    $saveDlg.Title = "検索結果の保存"
    $saveDlg.FileName = "LogSearchResult_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

    if ($saveDlg.ShowDialog() -eq "OK") {
      try {
        if ($saveDlg.FileName.EndsWith(".csv")) {
          $script:resultList | Export-Csv -Path $saveDlg.FileName -Encoding UTF8 -NoTypeInformation
        }
        else {
          $sb = New-Object System.Text.StringBuilder
          [void]$sb.AppendLine("ファイル`t行番号`t内容`t生バイト(HEX)")
          foreach ($item in $script:resultList) {
            [void]$sb.AppendLine("$($item.FilePath)`t$($item.LineNo)`t$($item.Text)`t$($item.Hex)")
          }
          [System.IO.File]::WriteAllText($saveDlg.FileName, $sb.ToString(), [System.Text.Encoding]::UTF8)
        }
        [System.Windows.Forms.MessageBox]::Show("保存が完了しました。")
      }
      catch {
        [System.Windows.Forms.MessageBox]::Show("保存中にエラーが発生しました:`n$($_.Exception.Message)")
      }
    }
  })

$listView.Add_KeyDown({
    param($sender, $e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::C) {
      & $script:CopySelectedItems $false
      $e.Handled = $true
    }
  })

$btnFolder.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") {
      $txtFolder.Text = $dlg.SelectedPath
    }
  })

function Stop-Search {
  if ($null -ne $script:timer) {
    $script:timer.Stop()
    $script:timer.Dispose()
    $script:timer = $null
  }
  if ($null -ne $script:pauseEvent) {
    $script:pauseEvent.Set()
    $script:pauseEvent.Dispose()
    $script:pauseEvent = $null
  }
  if ($null -ne $script:psInstance) {
    $script:psInstance.Stop()
    $script:psInstance.Dispose()
    $script:psInstance = $null
  }
  $script:isUpdatingUI = $false
  $script:searchState = "Stopped"
  $btnSearch.Text = "検索"
}

$btnReset.Add_Click({
    Stop-Search
    $script:resultQueue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
    $script:resultList.Clear()
    $listView.VirtualListSize = 0
    $lblStatus.Text = "リセットしました ($SCRIPT_VERSION)"
  })

$btnSearch.Add_Click({
    if ($script:searchState -eq "Searching") {
      $script:searchState = "Paused"
      $script:pauseEvent.Reset() | Out-Null
      $btnSearch.Text = "再開"
      $lblStatus.Text = "一時中断中... ($($script:resultList.Count) 件表示中)"
      return
    }

    if ($script:searchState -eq "Paused") {
      $script:searchState = "Searching"
      $script:pauseEvent.Set() | Out-Null
      $btnSearch.Text = "一時中断"
      $lblStatus.Text = "検索中... ($($script:resultList.Count) 件ヒット)"
      return
    }

    $folder = $txtFolder.Text
    if (![System.IO.Directory]::Exists($folder)) {
      [System.Windows.Forms.MessageBox]::Show("フォルダが存在しません")
      return
    }

    if ($null -ne $script:pauseEvent) {
      $script:pauseEvent.Dispose()
    }
    $script:pauseEvent = New-Object System.Threading.ManualResetEvent $true

    $script:psInstance = [PowerShell]::Create()
    $runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
    $runspace.Open()

    $runspace.SessionStateProxy.SetVariable("SharedQueue", $script:resultQueue)
    $runspace.SessionStateProxy.SetVariable("PauseEvent", $script:pauseEvent)
    $script:psInstance.Runspace = $runspace

    $workerScriptPath = Join-Path $PSScriptRoot "SearchWorker.ps1"

    $script:psInstance.AddScript((Get-Content -Raw $workerScriptPath)).AddArgument($folder).AddArgument($txtKeyword.Text).AddArgument($chkFixGarbled.Checked).AddArgument($chkFF14Mode.Checked).AddArgument($PSScriptRoot) | Out-Null

    $script:asyncResult = $script:psInstance.BeginInvoke()

    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 50
    $script:searchState = "Searching"
    $btnSearch.Text = "一時中断"
    $lblStatus.Text = "ログファイルバッファ中…"

    $script:timer.Add_Tick({
        if ($script:isUpdatingUI) {
          return
        }
        $script:isUpdatingUI = $true

        try {
          if ($script:searchState -eq "Paused") {
            return
          }

          $addedCount = 0
          $itemObj = $null
          while ($script:resultQueue.TryDequeue([ref]$itemObj)) {
            if ($null -ne $itemObj) {
              $script:resultList.Add($itemObj)
              $addedCount++
            }
          }

          if ($addedCount -gt 0) {
            Suspend-Drawing $listView
            try {
              $listView.VirtualListSize = $script:resultList.Count
            }
            finally {
              Resume-Drawing $listView
            }
            $lblStatus.Text = "検索中... ($($script:resultList.Count) 件ヒット)"
          }

          if ($script:asyncResult.IsCompleted -and $script:resultQueue.IsEmpty) {
            $lblStatus.Text = "検索完了 (合計: $($script:resultList.Count) 件ヒット) - $SCRIPT_VERSION"
            Stop-Search
          }
        }
        finally {
          $script:isUpdatingUI = $false
        }
      })

    $script:timer.Start()
  })

$form.Add_FormClosed({
   Stop-Search
   [System.Environment]::Exit(0)
 })

$form.ShowDialog()
