<#
.SYNOPSIS
  方案A（Bailian + SiliconFlow）Key 连通性自检。
  不启动应用，直接打三家端点，快速确认 Key 有效、模型可用。

.EXAMPLE
  # 先设置环境变量
  $env:BAILIAN_API_KEY="sk-xxx"
  $env:SILICONFLOW_API_KEY="sk-yyy"
  powershell -ExecutionPolicy Bypass -File .\scripts\eval\check-providers.ps1
#>
[CmdletBinding()]
param(
    [string]$BailianKey = $env:BAILIAN_API_KEY,
    [string]$SiliconFlowKey = $env:SILICONFLOW_API_KEY,
    [int]$TimeoutSec = 30
)

$ErrorActionPreference = "Continue"
$results = New-Object System.Collections.Generic.List[object]

function Invoke-Json {
    param([string]$Name, [string]$Url, [hashtable]$Headers, [string]$Body)
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $resp = Invoke-RestMethod -Uri $Url -Method Post -Headers $Headers -ContentType "application/json; charset=utf-8" -Body ([System.Text.Encoding]::UTF8.GetBytes($Body)) -TimeoutSec $TimeoutSec
        $sw.Stop()
        return [pscustomobject]@{ ok = $true; resp = $resp; ms = $sw.ElapsedMilliseconds; err = $null }
    } catch {
        $sw.Stop()
        $msg = $_.Exception.Message
        if ($_.Exception.Response) {
            try {
                $sr = New-Object System.IO.StreamReader($_.Exception.Response.GetResponseStream())
                $msg = "$msg | body=" + $sr.ReadToEnd()
            } catch { }
        }
        return [pscustomobject]@{ ok = $false; resp = $null; ms = $sw.ElapsedMilliseconds; err = $msg }
    }
}

Write-Host "==== Ragent 方案A Key 自检 ===="
Write-Host ("BAILIAN_API_KEY     : {0}" -f $(if ($BailianKey) { "已设置" } else { "缺失" }))
Write-Host ("SILICONFLOW_API_KEY : {0}" -f $(if ($SiliconFlowKey) { "已设置" } else { "缺失" }))
Write-Host ""

# 1) Bailian Chat: qwen-plus
if ($BailianKey) {
    $body = '{"model":"qwen-plus","messages":[{"role":"user","content":"ping"}],"max_tokens":1,"stream":false}'
    $r = Invoke-Json "bailian-chat" "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions" @{ Authorization = "Bearer $BailianKey" } $body
    $ok = $r.ok -and $r.resp.choices.Count -ge 1
    $results.Add([pscustomobject]@{ capability = "Chat (qwen-plus)"; provider = "bailian"; pass = $ok; ms = $r.ms; detail = $(if ($ok) { "choices=" + $r.resp.choices.Count } else { $r.err }) })
} else {
    $results.Add([pscustomobject]@{ capability = "Chat (qwen-plus)"; provider = "bailian"; pass = $false; ms = $null; detail = "未设置 BAILIAN_API_KEY" })
}

# 2) SiliconFlow Embedding: Qwen/Qwen3-Embedding-8B
if ($SiliconFlowKey) {
    $body = '{"model":"Qwen/Qwen3-Embedding-8B","input":["ping"],"dimensions":1536,"encoding_format":"float"}'
    $r = Invoke-Json "siliconflow-embedding" "https://api.siliconflow.cn/v1/embeddings" @{ Authorization = "Bearer $SiliconFlowKey" } $body
    $dim = if ($r.ok -and $r.resp.data -and $r.resp.data.Count -ge 1) { $r.resp.data[0].embedding.Count } else { 0 }
    $ok = ($dim -gt 0)
    $results.Add([pscustomobject]@{ capability = "Embedding (Qwen3-Embedding-8B)"; provider = "siliconflow"; pass = $ok; ms = $r.ms; detail = $(if ($ok) { "dim=" + $dim } else { $r.err }) })
} else {
    $results.Add([pscustomobject]@{ capability = "Embedding (Qwen3-Embedding-8B)"; provider = "siliconflow"; pass = $false; ms = $null; detail = "未设置 SILICONFLOW_API_KEY" })
}

# 3) Bailian Rerank: qwen3-rerank（可选）
if ($BailianKey) {
    $body = '{"model":"qwen3-rerank","input":{"query":"空调报修","documents":["空调报修流程","发票开具说明"]},"parameters":{"top_n":2,"return_documents":true}}'
    $r = Invoke-Json "bailian-rerank" "https://dashscope.aliyuncs.com/api/v1/services/rerank/text-rerank/text-rerank" @{ Authorization = "Bearer $BailianKey" } $body
    $ok = $r.ok -and $r.resp.output.results.Count -ge 1
    $results.Add([pscustomobject]@{ capability = "Rerank (qwen3-rerank)"; provider = "bailian"; pass = $ok; ms = $r.ms; detail = $(if ($ok) { "results=" + $r.resp.output.results.Count } else { $r.err }) })
} else {
    $results.Add([pscustomobject]@{ capability = "Rerank (qwen3-rerank)"; provider = "bailian"; pass = $false; ms = $null; detail = "未设置 BAILIAN_API_KEY" })
}

Write-Host ("{0,-34} {1,-12} {2,-6} {3,8}  {4}" -f "capability", "provider", "pass", "ms", "detail")
Write-Host ("-" * 100)
foreach ($r in $results) {
    $mark = if ($r.pass) { "PASS" } else { "FAIL" }
    Write-Host ("{0,-34} {1,-12} {2,-6} {3,8}  {4}" -f $r.capability, $r.provider, $mark, $r.ms, $r.detail)
}

$failed = @($results | Where-Object { -not $_.pass })
Write-Host ""
if ($failed.Count -eq 0) {
    Write-Host "[OK] 全部通过，可以启动应用跑评测。"
    exit 0
} else {
    Write-Host ("[X] {0} 项失败，请检查 Key / 账户额度 / 模型开通状态。" -f $failed.Count)
    exit 1
}
