param($folderPath, $keyword, $fixGarbled, $ff14Mode, $scriptDir)

if ([string]::IsNullOrEmpty($scriptDir)) {
  $scriptDir = $PSScriptRoot
}

try {
  $modulePath = Join-Path $scriptDir "FF14LogDecoder.psm1"
  if (Test-Path $modulePath) {
    Import-Module $modulePath -Force
  } else {
    throw "Decoder module not found at: $modulePath"
  }

  $isAllMatch = [string]::IsNullOrWhiteSpace($keyword)
  if (-not [System.IO.Directory]::Exists($folderPath)) {
    throw "Target folder does not exist: $folderPath"
  }

  $files = [System.IO.Directory]::GetFiles($folderPath, "*", [System.IO.SearchOption]::AllDirectories)

  $latin1 = [System.Text.Encoding]::GetEncoding("iso-8859-1")
  $sjis = [System.Text.Encoding]::GetEncoding("shift_jis")
  $utf8 = [System.Text.Encoding]::UTF8

  foreach ($filePath in $files) {
    if ($null -ne $PauseEvent) {
      $PauseEvent.WaitOne() | Out-Null
    }

    try {
      if (-not [System.IO.File]::Exists($filePath)) {
        continue
      }
      $bytes = [System.IO.File]::ReadAllBytes($filePath)
      if ($null -eq $bytes -or $bytes.Length -eq 0) {
        continue
      }

      if ($ff14Mode -and (Get-Command "Convert-FF14LogRecords" -ErrorAction SilentlyContinue)) {
        $records = Convert-FF14LogRecords $bytes
        $lineNo = 0

        foreach ($rec in $records) {
          $lineNo++
          $displayText = $rec.Text
          if ($null -ne $rec.Timestamp) {
            $displayText = "[" + $rec.Timestamp.ToString("yyyy-MM-dd HH:mm:ss") + "] " + $displayText
          }
          $displayText = $displayText.Trim()
          if ([string]::IsNullOrWhiteSpace($displayText)) {
            continue
          }

          $isMatch = $false
          if ($isAllMatch) {
            $isMatch = $true
          }
          elseif ($displayText.IndexOf($keyword, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isMatch = $true
          }

          if ($isMatch -and $null -ne $SharedQueue) {
            $relativePath = $filePath
            if ($filePath.StartsWith($folderPath, [System.StringComparison]::OrdinalIgnoreCase)) {
              $relativePath = $filePath.Substring($folderPath.Length).TrimStart("\", "/")
            }

            $SharedQueue.Enqueue([PSCustomObject]@{
                FilePath = $relativePath
                LineNo   = $lineNo
                Text     = $displayText
                Hex      = $rec.RawHex
              })
          }
        }
        continue
      }

      $contentString = ""
      if ($fixGarbled) {
        try {
          $rawString = $latin1.GetString($bytes)
          $rawBytes = $latin1.GetBytes($rawString)
          $contentString = $utf8.GetString($rawBytes)
        }
        catch {
          $contentString = $utf8.GetString($bytes)
        }
      }
      else {
        try {
          $contentString = $sjis.GetString($bytes)
        }
        catch {
          $contentString = $utf8.GetString($bytes)
        }
      }

      if ([string]::IsNullOrEmpty($contentString)) {
        continue
      }

      $lines = $contentString -split "\r?\n"
      $lineNo = 0

      foreach ($lineText in $lines) {
        $lineNo++
        $isMatch = $false

        if ($isAllMatch) {
          $isMatch = $true
        }
        else {
          if ($lineText.IndexOf($keyword, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
            $isMatch = $true
          }
        }

        if ($isMatch) {
          if ($null -ne $SharedQueue) {
            $relativePath = $filePath
            if ($filePath.StartsWith($folderPath, [System.StringComparison]::OrdinalIgnoreCase)) {
              $relativePath = $filePath.Substring($folderPath.Length).TrimStart("\", "/")
            }

            $SharedQueue.Enqueue([PSCustomObject]@{
                FilePath = $relativePath
                LineNo   = $lineNo
                Text     = $lineText
                Hex      = ""
              })
          }
        }
      }
    }
    catch {
      if ($null -ne $SharedQueue) {
        $SharedQueue.Enqueue([PSCustomObject]@{
            FilePath = "[FILE ERROR]"
            LineNo   = 0
            Text     = $_.Exception.Message
            Hex      = ""
          })
      }
    }
  }
}
catch {
  if ($null -ne $SharedQueue) {
    $SharedQueue.Enqueue([PSCustomObject]@{
        FilePath = "[FATAL ERROR]"
        LineNo   = 0
        Text     = $_.Exception.Message
        Hex      = ""
      })
  }
}



