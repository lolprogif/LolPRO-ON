param(
  [Parameter(Mandatory=$true)][string]$ZipUrl,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$ExeName
)
$ErrorActionPreference = "Stop"
$zip = Join-Path $env:TEMP "LolPRO-ON-update.zip"
$tmp = Join-Path $env:TEMP "LolPRO-ON-update"
try {
  Invoke-WebRequest -Uri $ZipUrl -OutFile $zip
  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $source = $tmp
  $nested = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if ($nested -and -not (Test-Path (Join-Path $tmp $ExeName))) { $source = $nested.FullName }
  $procName = [IO.Path]::GetFileNameWithoutExtension($ExeName)
  while (Get-Process -Name $procName -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 1 }
  Get-ChildItem $source -Force | Where-Object { $_.Name -ne "accounts.sqlite3" } | ForEach-Object {
    Copy-Item $_.FullName -Destination $InstallDir -Recurse -Force
  }
  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  Start-Process (Join-Path $InstallDir $ExeName)
} catch {
  Add-Content (Join-Path $env:TEMP "LolPRO-ON-update-error.txt") $_
}
