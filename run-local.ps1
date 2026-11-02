# Launch Ragent locally, injecting model API keys from .env.local (gitignored).
# No OS-level persistent env vars required.
#
# Usage:
#   1) Create <repo>\.env.local with:
#        BAILIAN_API_KEY=sk-xxx
#        SILICONFLOW_API_KEY=sk-yyy
#   2) powershell -ExecutionPolicy Bypass -File .\run-local.ps1

[CmdletBinding()]
param(
    [string]$EnvFile = "",
    [string]$SpringProfile = "",
    [switch]$SkipKeys,
    [switch]$SkipBuild
)

$ErrorActionPreference = "Stop"

$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $EnvFile) { $EnvFile = Join-Path $root ".env.local" }

function Load-EnvFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Warning ".env.local not found: $Path (app will start with empty keys)"
        return
    }
    $count = 0
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $t = $line.Trim()
        if ($t -eq "" -or $t.StartsWith("#")) { continue }
        $idx = $t.IndexOf("=")
        if ($idx -lt 1) { continue }
        $k = $t.Substring(0, $idx).Trim()
        $v = $t.Substring($idx + 1).Trim().Trim('"').Trim("'")
        [Environment]::SetEnvironmentVariable($k, $v, "Process")
        $count++
    }
    Write-Host ("[i] loaded {0} vars from {1}" -f $count, $Path)
}

if (-not $SkipKeys) { Load-EnvFile -Path $EnvFile }

foreach ($k in @("BAILIAN_API_KEY", "SILICONFLOW_API_KEY", "AIHUBMIX_API_KEY", "MINERU_API_KEY")) {
    $v = [Environment]::GetEnvironmentVariable($k, "Process")
    $state = if ($v) { "set (****" + $v.Substring([Math]::Max(0, $v.Length - 4)) + ")" } else { "empty" }
    Write-Host ("    {0,-22} : {1}" -f $k, $state)
}

$mvnw = Join-Path $root "mvnw.cmd"

# sibling modules (framework / infra-ai) must be in the local repo before
# `-pl bootstrap` can resolve them.
if (-not $SkipBuild) {
    Write-Host "[i] installing modules (framework, infra-ai, mcp-server, bootstrap)..."
    & $mvnw -q -DskipTests install
    if ($LASTEXITCODE -ne 0) { Write-Error "maven install failed"; exit 1 }
}

$mvnArgs = @("spring-boot:run", "-pl", "bootstrap")
if ($SpringProfile) { $mvnArgs += @("-Dspring-boot.run.profiles=$SpringProfile") }

Write-Host ("[i] running: mvnw " + ($mvnArgs -join " "))
& $mvnw @mvnArgs
