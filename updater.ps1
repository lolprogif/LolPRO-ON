param(
    [string]$ManifestUrl = "https://raw.githubusercontent.com/lolprogif/LolPRO-ON/main/latest.json",
    [string]$InstallDir = (Split-Path -Parent $MyInvocation.MyCommand.Path)
)
$ErrorActionPreference = "Stop"
$gameName = "LolPRO-ON"
$exePath = Join-Path $InstallDir "$gameName.exe"
$temp = Join-Path $env:TEMP ("LolPRO-ON-update-" + [guid]::NewGuid().ToString("N"))
$zip = Join-Path $temp "update.zip"
$stage = Join-Path $temp "stage"
try {
    New-Item -ItemType Directory -Force -Path $stage | Out-Null
    Write-Host "Aguardando o jogo fechar..."
    $deadline = (Get-Date).AddSeconds(90)
    while ((Get-Process -Name $gameName -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    if (Get-Process -Name $gameName -ErrorAction SilentlyContinue) {
        throw "O jogo ainda está aberto. Feche o LolPRO-ON e tente novamente."
    }

    $manifest = Invoke-RestMethod -Uri $ManifestUrl -TimeoutSec 30
    if (-not $manifest.windows_url) { throw "Manifesto sem windows_url." }
    Invoke-WebRequest -Uri $manifest.windows_url -OutFile $zip -UseBasicParsing
    Expand-Archive -LiteralPath $zip -DestinationPath $stage -Force

    # Alguns pacotes guardam os arquivos dentro de uma subpasta; localizar o executável.
    $sourceExe = Get-ChildItem -Path $stage -Filter "$gameName.exe" -Recurse | Select-Object -First 1
    if (-not $sourceExe) { throw "O pacote baixado não contém $gameName.exe." }
    $sourceRoot = $sourceExe.Directory.FullName

    # Preservar o banco local de contas se estiver ao lado do executável.
    $db = Join-Path $InstallDir "accounts.sqlite3"
    $dbBackup = Join-Path $temp "accounts.sqlite3"
    if (Test-Path $db) { Copy-Item $db $dbBackup -Force }

    Get-ChildItem -LiteralPath $sourceRoot -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $InstallDir -Recurse -Force
    }
    if (Test-Path $dbBackup) { Copy-Item $dbBackup $db -Force }
    if (-not (Test-Path $exePath)) { throw "Executável não encontrado após a atualização." }
    Start-Process -FilePath $exePath -WorkingDirectory $InstallDir
    Write-Host "LolPRO-ON atualizado."
}
catch {
    Write-Error $_
    Read-Host "A atualização falhou. Pressione Enter para fechar"
    exit 1
}
finally {
    Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue
}
