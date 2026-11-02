# Generate synthetic corpus files, eval dataset, and intent-tree seed SQL
# from synthetic-corpus.json.
#
# Usage:
#   powershell -ExecutionPolicy Bypass -File .\scripts\eval\generate-synthetic.ps1 -KbId <kbId>

[CmdletBinding()]
param(
    [string]$KbId = ""
)

$ErrorActionPreference = "Stop"
$root = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }

$json = Get-Content -LiteralPath (Join-Path $root "synthetic-corpus.json") -Raw -Encoding UTF8 | ConvertFrom-Json

$corpusDir = Join-Path $root "synthetic-corpus"
New-Item -ItemType Directory -Path $corpusDir -Force | Out-Null

# 1) corpus files
$n = 0
foreach ($d in $json.docs) {
    $content = "# " + $d.title + "`n`n" + $d.body + "`n"
    [System.IO.File]::WriteAllText((Join-Path $corpusDir ($d.code + ".txt")), $content, (New-Object System.Text.UTF8Encoding($false)))
    $n++
}
Write-Host ("[i] wrote {0} corpus files -> {1}" -f $n, $corpusDir)

# 2) eval dataset
$qmap = @{}
foreach ($q in $json.queries) {
    if ($q.intent) {
        if (-not $qmap.ContainsKey($q.intent)) { $qmap[$q.intent] = @() }
        if ($qmap[$q.intent].Count -lt 3) { $qmap[$q.intent] += $q.q }
    }
}
$sb = New-Object System.Text.StringBuilder
foreach ($q in $json.queries) {
    $refs = @($q.refs)
    $refJson = "[" + (($refs | ForEach-Object { '"' + $_ + '"' }) -join ",") + "]"
    $line = '{"id":"' + $q.id + '","question":"' + $q.q + '","reference_doc_ids":' + $refJson + ',"intent_l2":"' + $q.intent + '","category":"' + $q.cat + '"}'
    [void]$sb.AppendLine($line)
}
$datasetPath = Join-Path $root "dataset-large.jsonl"
[System.IO.File]::WriteAllText($datasetPath, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("[i] wrote {0} queries -> {1}" -f $json.queries.Count, $datasetPath)

# 3) intent tree seed SQL
$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine("-- Intent tree seed generated from synthetic-corpus.json")
[void]$sql.AppendLine("DELETE FROM t_intent_node;")
$i = 0
foreach ($t in $json.tree) {
    $i++
    $id = "I" + $i.ToString("D4")
    $parent = if ($t.parent) { "'" + $t.parent + "'" } else { "NULL" }
    $desc = if ($t.desc) { ($t.desc -replace "'", "''") } else { "" }
    $kb = if ($KbId) { "'" + $KbId + "'" } else { "NULL" }
    $coll = if ($t.level -eq 2) { "'" + $json.kb.collection + "'" } else { "NULL" }
    $examples = "[]"
    if ($t.level -eq 2 -and $qmap.ContainsKey($t.code)) {
        $examples = "[" + (($qmap[$t.code] | ForEach-Object { '"' + $_ + '"' }) -join ",") + "]"
    }
    $examplesEsc = $examples -replace "'", "''"
    [void]$sql.AppendLine(("INSERT INTO t_intent_node (id, kb_id, intent_code, name, level, parent_code, description, examples, collection_name, kind, sort_order, enabled, deleted) VALUES ('{0}', {1}, '{2}', '{3}', {4}, {5}, '{6}', '{7}', {8}, 0, {9}, 1, 0);" -f $id, $kb, $t.code, $t.name, $t.level, $parent, $desc, $examplesEsc, $coll, $i))
}
$sqlPath = Join-Path $root "intent-seed.sql"
[System.IO.File]::WriteAllText($sqlPath, $sql.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("[i] wrote {0} intent nodes -> {1}" -f $json.tree.Count, $sqlPath)
