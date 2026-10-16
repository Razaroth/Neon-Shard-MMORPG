# Local Windows play launcher. No administrator privileges or editor required.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$version = '4.6.3'
$archiveName = "Godot_v$version-stable_win64.exe.zip"
$expectedHash = 'd44ea7ef5bab754cacd49d581b6062836b2eea12a82e1d183aebfad9cd8c7db2bd82513337bd657d6d2d5c04d46239c0570b029faf1343e81e8a2fa7b85dd83b'
$projectRoot = Split-Path -Parent $PSScriptRoot
$dataRoot = Join-Path $env:LOCALAPPDATA 'NeonShard'
$runtimeRoot = Join-Path $dataRoot "runtime\$version"
$godot = Join-Path $runtimeRoot "Godot_v$version-stable_win64.exe"
$godotConsole = Join-Path $runtimeRoot "Godot_v$version-stable_win64_console.exe"
$server = $null

try {
    if (-not [Environment]::Is64BitOperatingSystem) {
        throw 'This launcher requires 64-bit Windows.'
    }
    if (-not (Test-Path -LiteralPath $godot) -or -not (Test-Path -LiteralPath $godotConsole)) {
        Write-Host "Downloading Godot $version from its official release (first run only)..."
        New-Item -ItemType Directory -Force -Path $runtimeRoot | Out-Null
        $archive = Join-Path $runtimeRoot $archiveName
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/godotengine/godot/releases/download/$version-stable/$archiveName" -OutFile $archive
        if ((Get-FileHash -LiteralPath $archive -Algorithm SHA512).Hash.ToLowerInvariant() -ne $expectedHash) {
            Remove-Item -LiteralPath $archive -Force
            throw 'Godot download failed its official SHA-512 checksum. Please try again.'
        }
        Expand-Archive -LiteralPath $archive -DestinationPath $runtimeRoot -Force
        Remove-Item -LiteralPath $archive -Force
        if (-not (Test-Path -LiteralPath $godot) -or -not (Test-Path -LiteralPath $godotConsole)) { throw 'Godot runtime was not extracted correctly.' }
    }
    Write-Host 'Preparing game assets...'
    & $godotConsole --headless --path $projectRoot --editor --import --quit
    if ($LASTEXITCODE -ne 0) { throw 'Godot could not import the project.' }

    $session = Join-Path $dataRoot ('logs\' + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Force -Path $session | Out-Null
    $serverLog = Join-Path $session 'server.log'
    $serverError = Join-Path $session 'server-error.log'
    $world = Join-Path $dataRoot 'world'
    $server = Start-Process -FilePath $godot -ArgumentList @('--headless', '--path', "`"$projectRoot`"", '--', '--server', '--port', '2456', '--save-dir', "`"$world`"") -PassThru -RedirectStandardOutput $serverLog -RedirectStandardError $serverError -WindowStyle Hidden
    $ready = $false
    for ($attempt = 0; $attempt -lt 150; $attempt++) {
        Start-Sleep -Milliseconds 100
        $server.Refresh()
        if ($server.HasExited) { break }
        if ((Test-Path -LiteralPath $serverLog) -and (Select-String -LiteralPath $serverLog -Pattern 'SERVER_READY' -Quiet)) {
            $ready = $true
            break
        }
    }
    if (-not $ready) {
        if (Test-Path -LiteralPath $serverError) { Get-Content -LiteralPath $serverError | Write-Host }
        throw "Local server could not start. Close any other Neon Shard server using UDP 2456 and retry. Logs: $session"
    }
    Write-Host 'Choose a class and slot, leave the address at 127.0.0.1, and click CONNECT.'
    Write-Host 'Keep this launcher open while playing. Closing the game stops its local server.'
    $client = Start-Process -FilePath $godot -ArgumentList @('--path', "`"$projectRoot`"") -PassThru -Wait
    if ($client.ExitCode -ne 0) { throw "Game exited with code $($client.ExitCode). Server logs: $session" }
} catch {
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
} finally {
    if ($null -ne $server) {
        # Allow the observed disconnect to save the character before ending this server.
        Start-Sleep -Milliseconds 1000
        $server.Refresh()
        if (-not $server.HasExited) { Stop-Process -Id $server.Id -Force }
    }
}
