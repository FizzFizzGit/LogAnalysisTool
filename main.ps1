# PowerShell GUI Log Search Tool
#
# 構成:
#   Win32Helpers.ps1   - コンソール非表示 / WM_SETREDRAW描画抑制
#   UI-Layout.ps1      - フォーム・コントロールの生成
#   EventHandlers.ps1  - イベント配線・検索開始/停止ロジック
#   SearchWorker.ps1   - 別ランスペースで実行される検索処理本体
#
# 各ファイルはドットソース(.)で読み込むため、このファイルと同じスコープで実行され、
# $form や $listView などの変数をファイルをまたいでそのまま参照できる。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$SCRIPT_VERSION = "v1.0.1"

# --- 検索の状態を保持するスクリプトスコープ変数 ---
$script:psInstance = $null
$script:asyncResult = $null
$script:timer = $null
$script:resultQueue = [System.Collections.Concurrent.ConcurrentQueue[PSObject]]::new()
$script:resultList = [System.Collections.Generic.List[PSObject]]::new()
$script:isUpdatingUI = $false
$script:searchState = "Stopped"
$script:pauseEvent = $null

# ListViewにはScrollイベントがないため、Timer自体は残す。
# ただし、TimerではVirtualListSizeを毎回更新せず、
# TopItemのIndexが変化したときだけ「スクロールされた」と判断する。
# 何も操作していない間はTopItem.Indexが変化しないので、
# ListViewの再描画は発生しない。
$script:lastTopItemIndex = -1

# 検索開始直後はスクロールイベントが発生するとは限らない。
# そのため、最初の一定件数までは先行してListViewへ公開する。
$script:initialVirtualListSize = 1000

. (Join-Path $PSScriptRoot "Win32Helpers.ps1")
. (Join-Path $PSScriptRoot "UI-Layout.ps1")
. (Join-Path $PSScriptRoot "EventHandlers.ps1")

$form.ShowDialog()
