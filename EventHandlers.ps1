# イベント配線: ListViewの描画・選択・コピー・保存・検索開始/停止まわり。
# UI-Layout.ps1で作られたコントロール群(と main.ps1 の $script:resultList 等)を前提にする。

# ListViewへ最新の検索結果件数を反映する処理。
#
# 検索中はresultListの件数が増えても、ここを自動的には呼ばない。
# VirtualModeではVirtualListSizeの変更がListViewの再取得・再描画を
# 発生させるため、ユーザーがスクロールしたときなど、表示内容を
# 更新する必要があるタイミングだけ呼び出す。
$script:UpdateVirtualListSize = {
  $currentCount = $script:resultList.Count

  # 既に同じ件数ならVirtualListSizeを触らない。
  # 不要な再描画を避けるための最後の防波堤。
  if ($listView.VirtualListSize -eq $currentCount) {
    return
  }

  Suspend-Drawing $listView
  try {
    $listView.VirtualListSize = $currentCount
  }
  finally {
    Resume-Drawing $listView
  }
}

# 描画イベント
# --- 縞模様描画 (仮想モードなので RetrieveVirtualItem で1行ずつ作る) ---
$colorEven = [System.Drawing.Color]::White
$colorOdd = [System.Drawing.Color]::FromArgb(240, 244, 248)

function New-ListViewRowItem ($idx) {
  $data = $script:resultList[$idx]
  $item = New-Object System.Windows.Forms.ListViewItem([string]$data.FilePath)
  $item.SubItems.Add([string]$data.LineNo) | Out-Null
  $item.SubItems.Add([string]$data.Text) | Out-Null
  $item.BackColor = if ($idx % 2 -eq 0) { $colorEven } else { $colorOdd }
  return $item
}

# --- 表示範囲をまとめて事前構築するキャッシュ ---
#     大量件数(数十万行)をスクロールすると、1行ごとにRetrieveVirtualItemで
#     ListViewItemを作り直すPowerShellスクリプトブロックの呼び出しコストが積み重なり、
#     体感できるレベルのカクつき・ちらつきになる。
#     ListViewが「これから表示する範囲」を事前に教えてくれるCacheVirtualItemsで、
#     その範囲をまとめて1回だけ作っておき、RetrieveVirtualItemは配列参照だけにする。
$script:itemCache = $null
$script:cacheStartIndex = -1

$listView.Add_CacheVirtualItems({
    param($sourceSender, $cacheEventArgs)

    # 既にキャッシュ範囲が要求範囲を包含していれば作り直さない
    if ($null -ne $script:itemCache -and
      $script:cacheStartIndex -le $cacheEventArgs.StartIndex -and
      ($script:cacheStartIndex + $script:itemCache.Length - 1) -ge $cacheEventArgs.EndIndex) {
      return
    }

    $script:cacheStartIndex = $cacheEventArgs.StartIndex
    $length = $cacheEventArgs.EndIndex - $cacheEventArgs.StartIndex + 1
    $script:itemCache = [System.Windows.Forms.ListViewItem[]]::new($length)

    for ($k = 0; $k -lt $length; $k++) {
      $idx = $cacheEventArgs.StartIndex + $k
      if ($idx -lt $script:resultList.Count) {
        $script:itemCache[$k] = New-ListViewRowItem $idx
      }
    }
  })

$listView.Add_RetrieveVirtualItem({
    param($sourceSender, $retrieveEventArgs)

    if ($null -ne $script:itemCache -and
      $retrieveEventArgs.ItemIndex -ge $script:cacheStartIndex -and
      $retrieveEventArgs.ItemIndex -lt ($script:cacheStartIndex + $script:itemCache.Length)) {
      $cached = $script:itemCache[$retrieveEventArgs.ItemIndex - $script:cacheStartIndex]
      if ($null -ne $cached) {
        $retrieveEventArgs.Item = $cached
        return
      }
    }

    # キャッシュ範囲外からの要求(単発クリック等)は、その場で1件だけ作るフォールバック
    if ($retrieveEventArgs.ItemIndex -lt $script:resultList.Count) {
      $retrieveEventArgs.Item = New-ListViewRowItem $retrieveEventArgs.ItemIndex
    }
  })

# --- 行選択時のHEX表示処理 ---
$listView.Add_SelectedIndexChanged({
    if ($listView.SelectedIndices.Count -gt 0) {
      $selectedIndex = $listView.SelectedIndices[0]
      if ($selectedIndex -lt $script:resultList.Count) {
        $txtHexInspector.Text = $script:resultList[$selectedIndex].Hex
      }
    }
    else {
      $txtHexInspector.Text = ""
    }
  })

# --- コピー処理(右クリックメニュー / Ctrl+C 共通) ---
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

$listView.Add_KeyDown({
    param($eventSender, $keyEventArgs)
    if ($keyEventArgs.Control -and $keyEventArgs.KeyCode -eq [System.Windows.Forms.Keys]::C) {
      & $script:CopySelectedItems $false
      $keyEventArgs.Handled = $true
    }
  })

# --- 検索結果の保存(CSV/テキスト) ---
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
          $script:resultList |
            Select-Object FilePath, LineNo, Text, Hex |
            Export-Csv -Path $saveDlg.FileName -Encoding UTF8 -NoTypeInformation
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

# --- フォルダ参照 ---
$btnFolder.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($dlg.ShowDialog() -eq "OK") {
      $txtFolder.Text = $dlg.SelectedPath
    }
  })

# --- 検索の停止・後始末 ---
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
    $script:lastTopItemIndex = -1
    $script:itemCache = $null
    $script:cacheStartIndex = -1
    $listView.VirtualListSize = 0
    $lblStatus.Text = "リセットしました ($SCRIPT_VERSION)"
  })

# --- 検索の開始・一時中断・再開 ---
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

    # 検索結果が増えるたびに画面を再描画することを防ぐ。
    # 最初の1000件程度は先行してListViewへ公開する。
    # ユーザーがスクロールできず、スクロール位置の変化自体を検出できなくなるため。
    # ListViewにはScrollイベントがないため、現在の先頭行を
    # Timerで確認して、実際にスクロールされたときだけ
    # 最新のVirtualListSizeを反映する。
    $script:timer = New-Object System.Windows.Forms.Timer
    $script:timer.Interval = 500
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

          # TopItem.Indexが変化しない限りVirtualListSizeには触れないので、
          # 検索結果が増え続けていても、ユーザーが何もしていない間は
          # ListViewの再描画を発生させない。
          while ($script:resultQueue.TryDequeue([ref]$itemObj)) {
            if ($null -ne $itemObj) {
              $script:resultList.Add($itemObj)
              $addedCount++
            }
          }

          if ($addedCount -gt 0) {

            if ($listView.VirtualListSize -lt $script:initialVirtualListSize) {
              $newSize = [Math]::Min(
                $script:initialVirtualListSize,
                $script:resultList.Count
              )

              if ($newSize -ne $listView.VirtualListSize) {
                Suspend-Drawing $listView
                try {
                  $listView.VirtualListSize = $newSize
                }
                finally {
                  Resume-Drawing $listView
                }
              }
            }
            $lblStatus.Text = "検索中... ($($script:resultList.Count) 件ヒット)" # 件数表示だけは検索結果の取り込みに合わせて更新する。
          }

          if ($listView.Items.Count -gt 0 -and $listView.TopItem) {
            $topIndex = $listView.TopItem.Index

            if ($script:lastTopItemIndex -ne $topIndex) {
              $script:lastTopItemIndex = $topIndex

              # 上に手繰った場合は既にロード済みの範囲を見ているだけなので同期不要。
              # 下に手繰った場合も、見えている範囲がまだVirtualListSizeの内側なら不要。
              # 「これから見ようとしている範囲がロード済みを超える」時だけ同期する。
              $itemHeight = 20
              try {
                if ($listView.VirtualListSize -gt 0) {
                  $itemHeight = [Math]::Max(1, $listView.GetItemRect(0).Height)
                }
              }
              catch {
                $itemHeight = 20
              }
              $visibleRows = [Math]::Max(1, [Math]::Ceiling($listView.ClientSize.Height / $itemHeight))
              $lastVisibleIndex = $topIndex + $visibleRows

              if ($lastVisibleIndex -ge $listView.VirtualListSize -and $listView.VirtualListSize -lt $script:resultList.Count) {
                & $script:UpdateVirtualListSize
              }
            }
          }

          if ($script:asyncResult.IsCompleted -and $script:resultQueue.IsEmpty) {
            # 検索完了時は待ち時間を設けず、最後に追加された結果まで
            # 必ずListViewへ反映する。
            #
            # これにより、検索完了時にVirtualListSizeだけ古いまま残ることを防ぐ。
            # 検索終了時はユーザー操作を待たず、最後の結果まで即時反映する。
            & $script:UpdateVirtualListSize

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
