param([string]$Server = '.\SQLEXPRESS')
$ErrorActionPreference = 'Continue'
$allOk = $true

Write-Host ''
Write-Host 'Verificação da Biblioteca' -ForegroundColor Cyan
Write-Host '=========================' -ForegroundColor Cyan

$dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
if (-not $dotnet) {
    Write-Host '[FALTA] .NET SDK' -ForegroundColor Red
    $allOk = $false
} else {
    $sdks = & dotnet --list-sdks
    if ($sdks | Where-Object { $_ -match '^10\.' }) {
        Write-Host '[OK] .NET 10 SDK' -ForegroundColor Green
    } else {
        Write-Host '[FALTA] .NET 10 SDK (há outra versão instalada, mas o projeto requer a 10)' -ForegroundColor Red
        $allOk = $false
    }
}

$sqlcmd = Get-Command sqlcmd -ErrorAction SilentlyContinue
if (-not $sqlcmd) {
    Write-Host '[FALTA] utilitário sqlcmd' -ForegroundColor Red
    $allOk = $false
} else {
    Write-Host '[OK] sqlcmd' -ForegroundColor Green
    $null = & sqlcmd -S $Server -E -C -b -l 5 -t 5 -Q 'SET NOCOUNT ON; SELECT 1;'
    if ($LASTEXITCODE -eq 0) {
        Write-Host "[OK] SQL Server acessível em $Server" -ForegroundColor Green
    } else {
        Write-Host "[FALTA] Não foi possível conectar ao SQL Server em $Server" -ForegroundColor Red
        Write-Host 'Confirme se o SQL Server Express está instalado e se o serviço está iniciado.' -ForegroundColor Yellow
        $allOk = $false
    }
}

try {
    $portInUse = Get-NetTCPConnection -LocalPort 5180 -State Listen -ErrorAction Stop
    if ($portInUse) {
        Write-Host '[ATENÇÃO] A porta 5180 já está sendo usada por outro programa.' -ForegroundColor Yellow
    }
} catch {
    Write-Host '[OK] Porta 5180 disponível' -ForegroundColor Green
}

Write-Host ''
if ($allOk) {
    Write-Host 'Tudo pronto. Execute Iniciar-Biblioteca.cmd.' -ForegroundColor Green
    exit 0
}
Write-Host 'Instale ou corrija os itens marcados como FALTA e execute esta verificação novamente.' -ForegroundColor Red
exit 1
