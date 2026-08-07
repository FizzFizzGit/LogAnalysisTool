# FF14ログ解析・デコードモジュール
#
# 想定しているデータ構造:
#   [Unixタイムスタンプ: 4byte LE] [種別: 4byte LE整数] [色コード: 0x1Fが1個以上] [本文...]
#
# 2パス構成:
#   1パス目 (Find-RecordBoundaries): 本文には一切触れず、0x02...0x03タグはスキップしつつ、
#           「タイムスタンプ+種別+0x1F」のパターンに一致する位置だけを全部集める。
#   2パス目 (Convert-FF14LogRecords): 1パス目のリストをもとに、境界[n]〜境界[n+1]の直前を
#           1レコード分として切り出し、その範囲だけを本文変換する。
#
# こうすることで「タグの無いプレーンテキストのレコードが次のヘッダーに食い込む」問題が
# 構造的に発生しなくなる(2パス目に入る時点で、各レコードの範囲がすでに確定しているため)。

# ==========================================
# 1. 補助関数
# ==========================================

# --- 03終端(ETX)を探索し、進んだ位置を返す ---
function Find-EtxTerminal ([byte[]]$rawBytes, [int]$currentIndex, [int]$len) {
  $idx = $currentIndex
  while ($idx -lt $len -and $rawBytes[$idx] -ne 0x03) {
    $idx++
  }
  return $idx
}

# --- subType 0x12 (アイコン)の中で判明しているものは絵文字に変換 ---
function IconConversion ([byte[]]$rawBytes, [System.IO.MemoryStream]$ms, $start, $len) {
  $iconType = if ($start + 3 -lt $len) { $rawBytes[$start + 3] } else { -1 }
  if ($iconType -eq 0x4A) { Write-Utf8String $ms "🎲"; return $true }
  if ($iconType -eq 0x59) { Write-Utf8String $ms "🌸"; return $true }
  return $false
}

# --- テキストをメモリストリームに書き込む ---
function Write-Utf8String ([System.IO.MemoryStream]$ms, [string]$text) {
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
  $ms.Write($bytes, 0, $bytes.Length)
}

# ==========================================
# 2. 1パス目: 境界(レコードの先頭位置)だけを集める
# ==========================================

function Find-RecordBoundaries ([byte[]]$rawBytes) {
  $boundaries = [System.Collections.Generic.List[int]]::new()
  $len = $rawBytes.Length
  $i = 0

  while ($i -lt $len) {
    # [ts:4][種別:4][0x1F] の形かどうかを先にチェックする。
    # (タイムスタンプの先頭バイトが偶然0x02になることがあり、
    #  0x02判定を先にすると本物のタイムスタンプをタグの中身だと
    #  誤解してまるごと読み飛ばしてしまうため、判定の順序が重要)
    if ($i + 9 -le $len -and $rawBytes[$i + 7] -eq 0x00 -and $rawBytes[$i + 8] -eq 0x1F) {
      $unixTime = [System.BitConverter]::ToUInt32($rawBytes, $i)
      if ($unixTime -ge 1577836800 -and $unixTime -le 2000000000) {
        $boundaries.Add($i)
        $i += 9
        continue
      }
    }

    # 0x02...0x03 タグの中身は境界候補から除外する
    # (タグの中の数値がたまたまタイムスタンプらしく見えて誤検出するのを防ぐため)
    if ($rawBytes[$i] -eq 0x02) {
      $i = (Find-EtxTerminal $rawBytes ($i + 1) $len) + 1
      continue
    }

    $i++
  }

  return $boundaries
}

# ==========================================
# 3. 2パス目: 境界リストをもとに1レコードずつ本文変換する
# ==========================================

# --- 変換後テキスト中の 0x1F を目印に、その前後が完全一致する重複を取り除く。
#     一致すれば手前のコピーと0x1Fごと削り、一致しなければ区切りとしてスペースに変える。
#     (Remove-LeadingNameEcho・Remove-LeadingTextEchoを統合したもの。
#      本物の0x1Fだけを基準にするので、"Non Nonon"のような自然な空白を
#      誤って重複と判定する心配が無い)
function Remove-DuplicateAroundBoundary ([string]$text) {
  while ($true) {
    $idx = $text.IndexOf([char]0x1F)
    if ($idx -lt 0) {
      return $text
    }

    $prefix = $text.Substring(0, $idx)
    $rest = $text.Substring($idx + 1)

    if ($prefix.Length -gt 0 -and $rest.Length -ge $prefix.Length -and $rest.Substring(0, $prefix.Length) -eq $prefix) {
      $text = $rest
    }
    else {
      $text = $prefix + " " + $rest
    }
  }
}

function Convert-FF14TagBytes ([byte[]]$rawBytes) {
  $ms = [System.IO.MemoryStream]::new()
  $len = $rawBytes.Length
  $i = 0

  while ($i -lt $len) {
    $b = $rawBytes[$i]

    if ($b -eq 0x02) {
      $start = $i
      $etx = Find-EtxTerminal $rawBytes ($i + 1) $len

      if ($etx -ge $len) {
        # 閉じる0x03が見つからなかった場合、タグとして解釈せずそのまま出力する
        $ms.WriteByte($b)
        $i = $start + 1
        continue
      }

      $subType = if ($start + 1 -lt $len) { $rawBytes[$start + 1] } else { -1 }

      if ($subType -eq 0x12) {
        if (IconConversion $rawBytes $ms $start $len) {
          $i = $etx + 1
          continue
        }
      }

      if ($subType -eq 0x27 -or $subType -eq 0x48 -or $subType -eq 0x49) {
        # 名前リンク等: タグ自体は削除する(直後にプレーンテキストの本体が続くため)
        $i = $etx + 1
        continue
      }

      # 未対応のタグは中身が分かるようにHEXで残す
      $blockLen = ($etx - $start) + 1
      $blockBytes = [Byte[]]::new($blockLen)
      [Array]::Copy($rawBytes, $start, $blockBytes, 0, $blockLen)
      Write-Utf8String $ms ("[" + (([System.BitConverter]::ToString($blockBytes)) -replace "-", " ") + "]")
      $i = $etx + 1
      continue
    }

    $ms.WriteByte($b)
    $i++
  }

  return [System.Text.Encoding]::UTF8.GetString($ms.ToArray())
}

function Convert-FF14LogRecords ([byte[]]$rawBytes) {
  $records = [System.Collections.Generic.List[PSObject]]::new()
  if ($null -eq $rawBytes -or $rawBytes.Length -eq 0) {
    return $records
  }

  $boundaries = Find-RecordBoundaries $rawBytes
  if ($boundaries.Count -eq 0) {
    return $records
  }

  for ($idx = 0; $idx -lt $boundaries.Count; $idx++) {
    $tsStart = $boundaries[$idx]
    $unixTime = [System.BitConverter]::ToUInt32($rawBytes, $tsStart)
    $timestamp = [DateTimeOffset]::FromUnixTimeSeconds($unixTime).ToLocalTime()

    # ヘッダー: タイムスタンプ(4) + 種別(4) の後に続く 0x1F の連続をスキップする
    $bodyStart = $tsStart + 8
    while ($bodyStart -lt $rawBytes.Length -and $rawBytes[$bodyStart] -eq 0x1F) {
      $bodyStart++
    }

    # フッター: 境界リスト数未満ならば次境界が現境界終端になる。以上ならバイトリスト長が終端になる。
    $bodyEnd = if ($idx + 1 -lt $boundaries.Count) { $boundaries[$idx + 1] } else { $rawBytes.Length }
    if ($bodyEnd -le $bodyStart) { continue }

    # 生バイトリストを生成
    $rawSegment = [Byte[]]::new($bodyEnd - $tsStart)
    [Array]::Copy($rawBytes, $tsStart, $rawSegment, 0, $rawSegment.Length)
    $hex = [System.BitConverter]::ToString($rawSegment) -replace "-", " "

    # 本文部分をフィルタする
    $bodyBytes = [Byte[]]::new($bodyEnd - $bodyStart)
    [Array]::Copy($rawBytes, $bodyStart, $bodyBytes, 0, $bodyBytes.Length)
    $text = (Convert-FF14TagBytes $bodyBytes).Trim()
    $text = Remove-DuplicateAroundBoundary $text

    # 元データの時点で既に壊れているバイト(U+FFFD)が、次のレコードの直前に
    # 紛れ込むことがある。値は復元できないので末尾のみ削る。
    $text = $text.TrimEnd([char]0xFFFD)

    # レコードリストに追加
    $records.Add([PSCustomObject]@{
        Timestamp = $timestamp
        Text      = $text
        RawHex    = $hex
      })
  }

  return $records
}

Export-ModuleMember -Function Convert-FF14LogRecords
