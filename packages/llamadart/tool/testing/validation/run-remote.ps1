param([Parameter(Mandatory=$true)][string]$Profile)
$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
$exitCode = 1
$ownsRun = $false
try {
    New-Item -ItemType Directory -Path '.started' -ErrorAction Stop | Out-Null
    $ownsRun = $true
    New-Item -ItemType Directory -Path 'results' -Force | Out-Null
    $manifest = Get-Content 'bundle-manifest.json' -Raw | ConvertFrom-Json
    foreach ($entry in $manifest.files.PSObject.Properties) {
        $name = $entry.Name
        if ($name -match '(^/|\\|(^|/)\.\.(/|$))') { throw 'Unsafe bundle member' }
        $file = Get-Item -LiteralPath $name
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Symlink in bundle' }
        if ($file.Length -ne $entry.Value.bytes) { throw 'Bundle size mismatch' }
        if ((Get-FileHash -LiteralPath $name -Algorithm SHA256).Hash.ToLower() -ne $entry.Value.sha256) {
            throw 'Bundle checksum mismatch'
        }
    }
    nvidia-smi -q | Out-File -Encoding utf8 'results/gpu.txt'
    $process = Start-Process -FilePath '.\bin\llamadart-validate.exe' -PassThru -NoNewWindow `
        -ArgumentList @('--profile', $Profile, '--out', 'results', '--cache', 'model-cache', '--environment-file', 'environment.json') `
        -RedirectStandardOutput 'results/stdout.log' -RedirectStandardError 'results/stderr.log'
    if (-not $process.WaitForExit(1200000)) {
        taskkill /PID $process.Id /T /F | Out-Null
        throw 'Validation execution timeout'
    }
    $engineStatus = $process.ExitCode
    & '.\bin\llamadart-report.exe' 'results' '--native-log' 'results/stderr.log'
    $exitCode = $LASTEXITCODE
    if ($engineStatus -ne 0 -and $engineStatus -ne 1) { $exitCode = $engineStatus }
} catch {
    $_.Exception.Message | Out-File -Encoding utf8 'supervisor-error.txt'
} finally {
    if ($ownsRun) { [IO.File]::WriteAllText((Join-Path $PSScriptRoot 'exit-code.txt'), [string]$exitCode) }
}
exit $exitCode
