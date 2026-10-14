param(
    [string]$Server = '.\SQLEXPRESS',
    [int]$Port = 5180,
    [switch]$RedeLocal
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$project = Join-Path $projectRoot 'src/Biblioteca.Api/Biblioteca.Api.csproj'
if (-not (Get-Command dotnet -ErrorAction SilentlyContinue)) {
    throw 'O .NET 10 SDK não foi encontrado. Consulte COMO-RODAR-EM-OUTRO-PC.md.'
}
$sdkVersions = & dotnet --list-sdks
if ($LASTEXITCODE -ne 0 -or -not ($sdkVersions | Where-Object { $_ -match '^10\.' })) {
    throw 'Instale o .NET 10 SDK (não apenas o Runtime). Consulte COMO-RODAR-EM-OUTRO-PC.md.'
}
& (Join-Path $PSScriptRoot 'Initialize-Database.ps1') -Server $Server -Demo
if (-not $env:Bootstrap__AdminPassword) {
    $countOutput = & sqlcmd -S $Server -d 'BibliotecaCodex_20260930' -E -C -b -l 10 -t 15 -h -1 -W -Q "SET NOCOUNT ON; SELECT COUNT(*) FROM dbo.USUARIOS WHERE Perfil='ADMINISTRADOR';"
    if ($LASTEXITCODE -ne 0) { throw 'Não foi possível verificar o administrador inicial.' }
    $adminCount = [int](($countOutput | Where-Object { $_.Trim() -match '^\d+$' }) -join '')
    if ($adminCount -eq 0) {
    Write-Host 'Escolha a senha do usuário admin (primeira execução).'
    $secret = Read-Host 'Senha inicial (mínimo 10 caracteres)' -AsSecureString
    $plain = [System.Net.NetworkCredential]::new('', $secret).Password
    if ($plain.Length -lt 10 -or $plain.Length -gt 128) { throw 'Use entre 10 e 128 caracteres.' }
    $env:Bootstrap__AdminPassword = $plain
    }
}
$previousConnection = $env:ConnectionStrings__Biblioteca
$previousEnvironment = $env:ASPNETCORE_ENVIRONMENT
$previousAllowedHosts = $env:AllowedHosts
try {
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:ConnectionStrings__Biblioteca = "Server=$Server;Database=BibliotecaCodex_20260930;Integrated Security=True;Encrypt=True;TrustServerCertificate=True"
    $listenAddress = if ($RedeLocal) { '0.0.0.0' } else { '127.0.0.1' }
    if ($RedeLocal) { $env:AllowedHosts = '*' }
    Write-Host ''
    Write-Host 'Biblioteca pronta para iniciar.' -ForegroundColor Green
    if ($RedeLocal) {
        $localAddresses = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
            Where-Object {
                $_.IPAddress -notlike '127.*' -and
                $_.IPAddress -notlike '169.254.*' -and
                $_.InterfaceAlias -notmatch 'Loopback|vEthernet|Virtual|VPN'
            } |
            Select-Object -ExpandProperty IPAddress -Unique
        Write-Host 'No celular, conectado ao mesmo Wi-Fi, use um destes endereços:' -ForegroundColor Cyan
        foreach ($address in $localAddresses) {
            Write-Host "  http://${address}:$Port" -ForegroundColor Cyan
        }
        if (-not $localAddresses) {
            Write-Host "Descubra o IPv4 do computador com ipconfig e use http://IP-DO-PC:$Port" -ForegroundColor Cyan
        }
        Write-Host 'Se o Windows perguntar, permita o acesso pela rede privada.' -ForegroundColor Yellow
    } else {
        Write-Host "Quando aparecer 'Now listening', abra http://127.0.0.1:$Port no navegador." -ForegroundColor Cyan
    }
    Write-Host 'Mantenha esta janela aberta. Use Ctrl+C para encerrar.' -ForegroundColor Yellow
    Write-Host ''
    & dotnet run --project $project --no-launch-profile --urls "http://${listenAddress}:$Port"
} finally {
    $env:Bootstrap__AdminPassword = $null
    $env:ConnectionStrings__Biblioteca = $previousConnection
    $env:ASPNETCORE_ENVIRONMENT = $previousEnvironment
    $env:AllowedHosts = $previousAllowedHosts
    $plain = $null
}
