param(
  [Parameter(Mandatory=$true)][string]$ZipUrl,
  [Parameter(Mandatory=$true)][string]$InstallDir,
  [Parameter(Mandatory=$true)][string]$ExeName
)
$ErrorActionPreference = "Stop"
$zip = Join-Path $env:TEMP "LolPRO-ON-update.zip"
$tmp = Join-Path $env:TEMP "LolPRO-ON-update"
$log = Join-Path $env:TEMP "LolPRO-ON-update-error.txt"
try {
  # Baixa antes de fechar o jogo ou solicitar permissao administrativa.
  Invoke-WebRequest -Uri $ZipUrl -OutFile $zip
  if (-not (Test-Path $zip) -or (Get-Item $zip).Length -lt 1024) {
    throw "O pacote baixado esta vazio ou incompleto."
  }

  # Se o jogo estiver em Program Files, solicita elevacao do Windows.
  $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $principal = [Security.Principal.WindowsPrincipal]::new($identity)
  if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath,
      "-ZipUrl", $ZipUrl, "-InstallDir", $InstallDir, "-ExeName", $ExeName)
    $elevated = Start-Process -FilePath "powershell.exe" -ArgumentList $args -Verb RunAs -PassThru
    exit 0
  }

  if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
  Expand-Archive -Path $zip -DestinationPath $tmp -Force
  $source = $tmp
  $nested = Get-ChildItem $tmp -Directory | Select-Object -First 1
  if ($nested -and -not (Test-Path (Join-Path $tmp $ExeName))) {
    $source = $nested.FullName
  }
  if (-not (Test-Path (Join-Path $source $ExeName))) {
    throw "O executavel principal nao foi encontrado no pacote."
  }

  $procName = [IO.Path]::GetFileNameWithoutExtension($ExeName)
  while (Get-Process -Name $procName -ErrorAction SilentlyContinue) {
    Start-Sleep -Seconds 1
  }

  # Nunca substitui banco local de contas, arquivos de usuario ou configuracoes.
  $protected = @("accounts.sqlite3", "user", "userdata", "saves", "config")
  Get-ChildItem $source -Force | Where-Object { $protected -notcontains $_.Name.ToLowerInvariant() } | ForEach-Object {
    Copy-Item $_.FullName -Destination $InstallDir -Recurse -Force
  }

  Remove-Item $zip -Force -ErrorAction SilentlyContinue
  Start-Process (Join-Path $InstallDir $ExeName)
} catch {
  Add-Content -Path $log -Value ("{0} - {1}" -f (Get-Date -Format o), $_)
  try { Start-Process "notepad.exe" -ArgumentList $log } catch {}
  exit 1
}
