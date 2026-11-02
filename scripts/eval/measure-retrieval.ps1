<#
.SYNOPSIS
  Ragent 检索评测：调用 /rag/eval 计算 Hit@k / MRR / context_precision / context_recall / 意图 Top-1 / 延迟。

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\eval\measure-retrieval.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File .\scripts\eval\measure-retrieval.ps1 -Dataset .\scripts\eval\my.jsonl -Token "<token>" -Label baseline
#>
[CmdletBinding()]
param(
    [string]$BaseUrl = "http://localhost:9090/api/ragent",
    [string]$Dataset = "",
    [string]$Token = "",
    [string]$Label = "default",
    [string]$OutDir = "",
    [int]$TimeoutSec = 120
)

$ErrorActionPreference = "Stop"

$scriptRoot = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Dataset) { $Dataset = Join-Path $scriptRoot "dataset.sample.jsonl" }
if (-not $OutDir) { $OutDir = Join-Path $scriptRoot "out" }

function Test-Blank($v) {
    return ($null -eq $v) -or ([string]$v).Trim() -eq ""
}

function Get-Percentile {
    param([double[]]$Values, [double]$P)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $idx = [int][Math]::Ceiling($sorted.Count * $P) - 1
    if ($idx -lt 0) { $idx = 0 }
    if ($idx -ge $sorted.Count) { $idx = $sorted.Count - 1 }
    return [Math]::Round($sorted[$idx], 2)
}

function Get-Mean {
    param($Values)
    $arr = @($Values | Where-Object { $null -ne $_ })
    if ($arr.Count -eq 0) { return $null }
    $sum = 0.0
    foreach ($v in $arr) { $sum += [double]$v }
    return [Math]::Round($sum / $arr.Count, 4)
}

function Test-Hit {
    param([string[]]$Docs, [int]$K, $RefSet)
    $n = [Math]::Min($K, $Docs.Count)
    for ($j = 0; $j -lt $n; $j++) {
        if ($RefSet.Contains([string]$Docs[$j])) { return $true }
    }
    return $false
}

if (-not (Test-Path -LiteralPath $Dataset)) {
    throw "评测集不存在: $Dataset"
}
if (-not (Test-Path -LiteralPath $OutDir)) {
    New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
}

$lines = Get-Content -LiteralPath $Dataset -Encoding UTF8 | Where-Object { $_.Trim() -ne "" -and -not $_.TrimStart().StartsWith("#") }
Write-Host ("[i] 数据集: {0}  ({1} 条)" -f $Dataset, $lines.Count)
Write-Host ("[i] 服务:   {0}" -f $BaseUrl)
Write-Host ("[i] 标签:   {0}" -f $Label)
Write-Host ""

$headers = @{}
if (-not (Test-Blank $Token)) { $headers["Authorization"] = $Token }

$perQuery = New-Object System.Collections.Generic.List[object]
$hit1 = @(); $hit3 = @(); $hit5 = @(); $hit10 = @()
$mrr = @(); $prec = @(); $recall = @(); $intentAcc = @()
$lat = @()
$okCount = 0; $errCount = 0; $noRefCount = 0

$i = 0
foreach ($line in $lines) {
    $i++
    $rec = $null
    try { $rec = $line | ConvertFrom-Json } catch { Write-Warning "第 $i 行 JSON 解析失败，跳过"; continue }
    $qid = if (Test-Blank $rec.id) { "row$i" } else { $rec.id }
    $question = [string]$rec.question
    if (Test-Blank $question) { Write-Warning "$qid 缺 question，跳过"; continue }

    $refSet = New-Object System.Collections.Generic.HashSet[string]
    foreach ($r in @($rec.reference_doc_ids)) { if (-not (Test-Blank $r)) { [void]$refSet.Add([string]$r) } }

    $uri = "$BaseUrl/rag/eval?question=" + [System.Uri]::EscapeDataString($question)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $data = $null
    $status = "OK"
    try {
        $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -TimeoutSec $TimeoutSec
        $sw.Stop()
        if ($resp.code -ne "0" -or $null -eq $resp.data) {
            $status = "API_ERR:$($resp.code) $($resp.message)"
            $errCount++
        } else {
            $data = $resp.data
            $okCount++
        }
    } catch {
        $sw.Stop()
        $status = "EXCEPTION:$($_.Exception.Message)"
        $errCount++
    }

    $r1 = $null; $r3 = $null; $r5 = $null; $r10 = $null; $rr = $null; $p = $null; $rc = $null; $ia = $null; $latMs = $null
    if ($null -ne $data) {
        $latMs = [int]$data.latencyMs
        $lat += $latMs
        $docIds = @($data.retrievedDocIds | Where-Object { -not (Test-Blank $_) })

        if ($refSet.Count -gt 0) {
            $firstRank = 0
            for ($j = 0; $j -lt $docIds.Count; $j++) {
                if ($refSet.Contains([string]$docIds[$j])) { $firstRank = $j + 1; break }
            }
            $r1  = [double](Test-Hit $docIds 1  $refSet)
            $r3  = [double](Test-Hit $docIds 3  $refSet)
            $r5  = [double](Test-Hit $docIds 5  $refSet)
            $r10 = [double](Test-Hit $docIds 10 $refSet)
            $rr = if ($firstRank -gt 0) { 1.0 / $firstRank } else { 0.0 }
            $hit1 += $r1; $hit3 += $r3; $hit5 += $r5; $hit10 += $r10; $mrr += $rr

            $ctx = @($data.retrievedContextDocIds)
            $ctxNonEmpty = @($ctx | Where-Object { -not (Test-Blank $_) })
            if ($ctxNonEmpty.Count -gt 0) {
                $ctxMatched = @($ctxNonEmpty | Where-Object { $refSet.Contains([string]$_) })
                $p = [double]$ctxMatched.Count / $ctxNonEmpty.Count
                $prec += $p
            }
            $ctxUniqueRef = New-Object System.Collections.Generic.HashSet[string]
            foreach ($c in $ctxNonEmpty) { if ($refSet.Contains([string]$c)) { [void]$ctxUniqueRef.Add([string]$c) } }
            $rc = [double]$ctxUniqueRef.Count / $refSet.Count
            $recall += $rc
        } else {
            $noRefCount++
        }

        if (-not (Test-Blank $rec.intent_l2)) {
            $leaves = @($data.intentLeafIds)
            if ($leaves.Count -gt 0) {
                $ia = [double]((([string]$leaves[0]) -eq ([string]$rec.intent_l2)))
                $intentAcc += $ia
            }
        }
    }

    $perQuery.Add([pscustomobject]@{
        id = $qid; category = $rec.category; status = $status
        hit1 = $r1; hit3 = $r3; hit5 = $r5; hit10 = $r10
        mrr = $rr; context_precision = $p; context_recall = $rc
        intent_top1 = $ia; latency_ms = $latMs
        retrievedDocIds = (@($data.retrievedDocIds) -join "|")
    }) | Out-Null

    Write-Host ("[{0,3}/{1}] {2}  {3}  {4}ms" -f $i, $lines.Count, $qid, $status, $latMs)
}

$summary = [ordered]@{
    label = $Label
    baseUrl = $BaseUrl
    dataset = (Resolve-Path -LiteralPath $Dataset).Path
    generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    total = $lines.Count
    ok = $okCount
    error = $errCount
    noReference = $noRefCount
    metrics = [ordered]@{
        hit_at_1 = Get-Mean $hit1
        hit_at_3 = Get-Mean $hit3
        hit_at_5 = Get-Mean $hit5
        hit_at_10 = Get-Mean $hit10
        mrr = Get-Mean $mrr
        context_precision = Get-Mean $prec
        context_recall = Get-Mean $recall
        intent_top1_accuracy = Get-Mean $intentAcc
        retrieval_latency_avg_ms = Get-Mean $lat
        retrieval_latency_p50_ms = Get-Percentile $lat 0.50
        retrieval_latency_p95_ms = Get-Percentile $lat 0.95
    }
    sampleSizes = [ordered]@{
        hit = $hit1.Count
        context = $prec.Count
        intent = $intentAcc.Count
        latency = $lat.Count
    }
}

$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$safeLabel = ($Label -replace '[^\w\-]', '_')
$summaryPath = Join-Path $OutDir "$stamp-$safeLabel.summary.json"
$perQueryPath = Join-Path $OutDir "$stamp-$safeLabel.per-query.csv"

$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$perQuery | Export-Csv -LiteralPath $perQueryPath -NoTypeInformation -Encoding UTF8

Write-Host ""
Write-Host "==================== 结果 ===================="
$m = $summary.metrics
Write-Host ("Hit@1                : {0}" -f $m.hit_at_1)
Write-Host ("Hit@3                : {0}" -f $m.hit_at_3)
Write-Host ("Hit@5                : {0}" -f $m.hit_at_5)
Write-Host ("Hit@10               : {0}" -f $m.hit_at_10)
Write-Host ("MRR                  : {0}" -f $m.mrr)
Write-Host ("context_precision    : {0}" -f $m.context_precision)
Write-Host ("context_recall       : {0}" -f $m.context_recall)
Write-Host ("intent Top-1 acc     : {0}" -f $m.intent_top1_accuracy)
Write-Host ("retrieval latency avg: {0} ms" -f $m.retrieval_latency_avg_ms)
Write-Host ("retrieval latency p50: {0} ms" -f $m.retrieval_latency_p50_ms)
Write-Host ("retrieval latency p95: {0} ms" -f $m.retrieval_latency_p95_ms)
Write-Host ("成功/失败/无标准答案 : {0}/{1}/{2}   (样本量 hit={3}, intent={4}, latency={5})" -f $okCount, $errCount, $noRefCount, $summary.sampleSizes.hit, $summary.sampleSizes.intent, $summary.sampleSizes.latency)
Write-Host ""
Write-Host ("[✓] 汇总: {0}" -f $summaryPath)
Write-Host ("[✓] 明细: {0}" -f $perQueryPath)
