param([switch]$Check)
$projectRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$assets = @('index.html', 'app.js', 'styles.css', 'dates.js', 'booking-ui.js')
foreach ($asset in $assets) {
    $source = Join-Path $projectRoot "Frontend/$asset"
    $destination = Join-Path $projectRoot "src/main/resources/static/$asset"
    if ($Check) {
        if ((Get-FileHash -LiteralPath $source).Hash -ne (Get-FileHash -LiteralPath $destination).Hash) {
            throw "Frontend assets differ: $asset"
        }
    } else {
        Copy-Item -LiteralPath $source -Destination $destination
    }
}
Write-Output 'Frontend assets are synchronized.'
