param(
    [Parameter(Position = 0)]
    [ValidateSet('setup', 'game', 'vendor', 'build', 'serve')]
    [string] $Action = 'setup',
    [Parameter(Position = 1)]
    [int] $Port = 8080
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
    throw 'WSL2 is required. Install it from an elevated PowerShell with: wsl --install -d Ubuntu'
}

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$linuxRoot = (& wsl.exe wslpath -a $repoRoot | Out-String).Trim()
if ($LASTEXITCODE -ne 0 -or -not $linuxRoot) {
    throw 'Could not translate the repository path into WSL. Make sure a WSL2 distribution is installed.'
}

$script = switch ($Action) {
    'setup' { 'setup-linux.sh' }
    'game' { 'get-pokefirered.sh' }
    'vendor' { 'fetch-vendor.sh' }
    'build' { 'build-rom.sh' }
    'serve' { 'serve.mjs' }
}

if ($Action -eq 'serve') {
    if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
        throw 'Node.js 18 or newer is required to serve the site. Install Node.js for Windows, then try again.'
    }
    & node (Join-Path $PSScriptRoot $script) $Port
} else {
    & wsl.exe --cd $linuxRoot --exec bash "scripts/$script"
}

if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
