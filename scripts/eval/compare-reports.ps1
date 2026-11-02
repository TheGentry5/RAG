<#
.SYNOPSIS
  对比两次评测汇总（如 baseline vs 关闭 Rerank），输出指标变化与相对百分比。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\eval\compare-reports.ps1 `
    -Baseline .\scripts\eval\out\20261014-baseline.summary.json `
    -Variant  .\scripts\eval\out\20261014-no-rerank.summary.json
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Baseline,
    [Parameter(Mandatory = $true)][string]$Variant
)

$ErrorActionPreference = "Stop"
$b = Get-Content -LiteralPath $Baseline -Raw -Encoding UTF8 | ConvertFrom-Json
$v = Get-Content -LiteralPath $Variant -Raw -Encoding UTF8 | ConvertFrom-Json

$order = @(
    "hit_at_1", "hit_at_3", "hit_at_5", "hit_at_10",
    "mrr", "context_precision", "context_recall", "intent_top1_accuracy",
    "retrieval_latency_avg_ms", "retrieval_latency_p50_ms", "retrieval_latency_p95_ms"
)

Write-Host ("基线: {0} ({1})" -f $b.label, $b.dataset)
Write-Host ("对照: {0} ({1})" -f $v.label, $v.dataset)
Write-Host ""
Write-Host ("{0,-26} {1,12} {2,12} {3,12}" -f "metric", "baseline", "variant", "delta%")
Write-Host ("-" * 66)

foreach ($key in $order) {
    $bv = $b.metrics.$key
    $vv = $v.metrics.$key
    $delta = "n/a"
    if ($null -ne $bv -and $null -ne $vv -and [double]$bv -ne 0) {
        $pct = ([double]$vv - [double]$bv) / [double]$bv * 100.0
        $delta = ("{0:+0.0;-0.0}%" -f $pct)
    }
    Write-Host ("{0,-26} {1,12} {2,12} {3,12}" -f $key, $bv, $vv, $delta)
}

Write-Host ""
Write-Host "注：检索质量类指标越高越好；latency 类越低越好。delta% 为 variant 相对 baseline 的变化。"
