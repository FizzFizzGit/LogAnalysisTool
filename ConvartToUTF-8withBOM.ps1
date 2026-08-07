Get-ChildItem -Path . -Include *.ps1,*.psm1,*.psd1 -Recurse -File | ForEach-Object {
    $content = Get-Content -Path $_.FullName -Raw -Encoding UTF8
    Set-Content -Path $_.FullName -Value $content -Encoding UTF8
    Write-Host "変換完了: $($_.FullName)"
}
Format-Hex -Path ".\main.ps1" | Select-Object -First 1
Format-Hex -Path ".\FF14LogDecoder.psm1" | Select-Object -First 1
Format-Hex -Path ".\SearchWorker.ps1" | Select-Object -First 1

