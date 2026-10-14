param(
    [string]$Server = '.\SQLEXPRESS',
    [string]$Python = 'python',
    [int]$Port = 5181
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$apiRoot = Join-Path $projectRoot 'src/Biblioteca.Api'
$testDatabase = 'BibliotecaTest_' + (Get-Date -Format 'yyyyMMddHHmmss')
$testLog = Join-Path $projectRoot 'test-results'
New-Item -ItemType Directory -Path $testLog -Force | Out-Null
& (Join-Path $PSScriptRoot 'Initialize-Database.ps1') -Server $Server -Database $testDatabase
& dotnet build (Join-Path $apiRoot 'Biblioteca.Api.csproj') --nologo
if ($LASTEXITCODE -ne 0) { throw 'Build falhou.' }
$saved = @{}
foreach ($key in @('ASPNETCORE_ENVIRONMENT','ConnectionStrings__Biblioteca','Bootstrap__AdminPassword','BIBLIOTECA_ADMIN_PASSWORD','BIBLIOTECA_TEST_DATABASE','BIBLIOTECA_TEST_SERVER')) {
    $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
}
$process = $null
try {
    $env:ASPNETCORE_ENVIRONMENT = 'Development'
    $env:ConnectionStrings__Biblioteca = "Server=$Server;Database=$testDatabase;Integrated Security=True;Encrypt=True;TrustServerCertificate=True"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $random = New-Object byte[] 32
    $rng.GetBytes($random)
    $rng.Dispose()
    $env:Bootstrap__AdminPassword = [Convert]::ToBase64String($random)
    $env:BIBLIOTECA_ADMIN_PASSWORD = $env:Bootstrap__AdminPassword
    $env:BIBLIOTECA_TEST_DATABASE = $testDatabase
    $env:BIBLIOTECA_TEST_SERVER = $Server
    $apiDll = Join-Path $apiRoot 'bin/Debug/net10.0/Biblioteca.Api.dll'
    $apiArguments = '"' + $apiDll + '" --urls http://127.0.0.1:' + $Port
    $process = Start-Process -FilePath (Get-Command dotnet).Source -ArgumentList $apiArguments -WorkingDirectory $apiRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testLog 'api-out.log') -RedirectStandardError (Join-Path $testLog 'api-error.log')
    $ready = $false
    for ($attempt = 0; $attempt -lt 40; $attempt++) {
        if ($process.HasExited) { throw 'A API de testes encerrou. Consulte test-results/api-error.log.' }
        try {
            $health = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/health" -TimeoutSec 2
            if ($health.status -eq 'ok') { $ready = $true; break }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    if (-not $ready) { throw 'API não ficou pronta a tempo.' }
    & $Python (Join-Path $projectRoot 'tests/smoke.py') --base-url "http://127.0.0.1:$Port"
    if ($LASTEXITCODE -ne 0) { throw 'Há cenários HTTP com falha.' }
    & sqlcmd -S $Server -d $testDatabase -E -C -b -l 10 -t 30 -f 65001 -i (Join-Path $projectRoot 'tests/check-invariants.sql')
    if ($LASTEXITCODE -ne 0) { throw 'Falha nas invariantes do banco de dados.' }
    Write-Host "Testes concluídos. Banco isolado preservado para inspeção: $testDatabase"
} finally {
    if ($process -and -not $process.HasExited) { Stop-Process -Id $process.Id }
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
