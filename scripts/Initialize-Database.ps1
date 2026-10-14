param(
    [string]$Server = '.\SQLEXPRESS',
    [ValidatePattern('^Biblioteca[A-Za-z0-9_]{1,80}$')][string]$Database = 'BibliotecaCodex_20260930',
    [switch]$Demo
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not (Get-Command sqlcmd -ErrorAction SilentlyContinue)) { throw 'Instale sqlcmd ou execute os scripts SQL no SQL Server Management Studio.' }
$files = @('001-schema.sql', '002-procedures.sql')
if ($Demo) { $files += '003-demo.sql' }
foreach ($file in $files) {
    $sql = Get-Content -LiteralPath (Join-Path $projectRoot ('database/' + $file)) -Raw -Encoding utf8
    $sql = $sql.Replace('BibliotecaCodex_20260930', $Database)
    $tempFile = Join-Path ([IO.Path]::GetTempPath()) ("biblioteca-" + [guid]::NewGuid().ToString('N') + '.sql')
    try {
        # O arquivo temporário evita que o pipeline do PowerShell converta acentos
        # para a página de código do console antes de o sqlcmd recebê-los.
        [IO.File]::WriteAllText($tempFile, $sql, [Text.UTF8Encoding]::new($true))
        & sqlcmd -S $Server -E -C -b -l 10 -t 60 -f 65001 -i $tempFile
        if ($LASTEXITCODE -ne 0) { throw "Falha ao aplicar $file." }
        Write-Host "Aplicado: $file"
    }
    finally {
        Remove-Item -LiteralPath $tempFile -Force -ErrorAction SilentlyContinue
    }
}
Write-Host "Banco pronto: $Database em $Server"
