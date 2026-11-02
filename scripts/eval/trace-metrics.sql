-- =============================================================
-- Ragent 运行指标 SQL（PostgreSQL）
-- 用法: psql "postgresql://postgres:postgres@127.0.0.1:5432/ragent" -f scripts/eval/trace-metrics.sql
-- 说明: 用于产出 首包TTFT / 端到端延迟 / 成功率 / 无知识率 / 慢请求率，
--       以及入库各阶段耗时。默认统计最近 24 小时，可改 INTERVAL。
-- =============================================================

\echo '===== 1. 首包延迟 TTFT（P50/P95/样本量），按节点类型 ====='
SELECT node_type,
       COUNT(*)                                                          AS samples,
       ROUND(AVG(duration_ms)::numeric, 1)                               AS avg_ms,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_ms)         AS p50_ms,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms)         AS p95_ms,
       MAX(duration_ms)                                                  AS max_ms
FROM t_rag_trace_node
WHERE deleted = 0
  AND node_type IN ('LLM_TTFT', 'USER_TTFT')
  AND start_time >= NOW() - INTERVAL '24 hours'
GROUP BY node_type
ORDER BY node_type;

\echo '===== 2. 端到端延迟（成功请求），P50/P95 ====='
SELECT COUNT(*)                                                          AS success_runs,
       ROUND(AVG(duration_ms)::numeric, 1)                               AS avg_ms,
       PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY duration_ms)         AS p50_ms,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms)         AS p95_ms
FROM t_rag_trace_run
WHERE deleted = 0 AND status = 'SUCCESS'
  AND start_time >= NOW() - INTERVAL '24 hours';

\echo '===== 3. 成功率 / 错误率 ====='
SELECT COUNT(*) FILTER (WHERE status = 'SUCCESS')                        AS success,
       COUNT(*) FILTER (WHERE status = 'ERROR')                          AS error,
       COUNT(*)                                                          AS total,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'SUCCESS') / NULLIF(COUNT(*), 0), 1) AS success_rate_pct,
       ROUND(100.0 * COUNT(*) FILTER (WHERE status = 'ERROR')   / NULLIF(COUNT(*), 0), 1) AS error_rate_pct
FROM t_rag_trace_run
WHERE deleted = 0
  AND start_time >= NOW() - INTERVAL '24 hours';

\echo '===== 4. 无知识率（assistant 回复为“未检索到...”的占比）====='
SELECT COUNT(*) FILTER (WHERE content = '未检索到与问题相关的文档内容。') AS no_doc,
       COUNT(*)                                                          AS assistant_total,
       ROUND(100.0 * COUNT(*) FILTER (WHERE content = '未检索到与问题相关的文档内容。')
             / NULLIF(COUNT(*), 0), 1)                                   AS no_doc_rate_pct
FROM t_message
WHERE deleted = 0 AND role = 'assistant'
  AND create_time >= NOW() - INTERVAL '24 hours';

\echo '===== 5. 慢请求率（端到端 > 20s）====='
SELECT COUNT(*) FILTER (WHERE duration_ms > 20000)                       AS slow,
       COUNT(*)                                                          AS total,
       ROUND(100.0 * COUNT(*) FILTER (WHERE duration_ms > 20000) / NULLIF(COUNT(*), 0), 1) AS slow_rate_pct
FROM t_rag_trace_run
WHERE deleted = 0 AND status = 'SUCCESS'
  AND start_time >= NOW() - INTERVAL '24 hours';

\echo '===== 6. 各检索/编排节点平均耗时（定位瓶颈）====='
SELECT node_type,
       node_name,
       COUNT(*)                                                          AS samples,
       ROUND(AVG(duration_ms)::numeric, 1)                               AS avg_ms,
       PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY duration_ms)         AS p95_ms
FROM t_rag_trace_node
WHERE deleted = 0
  AND start_time >= NOW() - INTERVAL '24 hours'
GROUP BY node_type, node_name
ORDER BY avg_ms DESC
LIMIT 20;

\echo '===== 7. 入库各阶段耗时（解析/分块/向量化/落库）====='
SELECT COUNT(*)                                                          AS docs,
       SUM(chunk_count)                                                  AS total_chunks,
       ROUND(AVG(extract_duration)::numeric, 1)                          AS avg_extract_ms,
       ROUND(AVG(chunk_duration)::numeric, 1)                            AS avg_chunk_ms,
       ROUND(AVG(embed_duration)::numeric, 1)                            AS avg_embed_ms,
       ROUND(AVG(persist_duration)::numeric, 1)                          AS avg_persist_ms,
       ROUND(AVG(total_duration)::numeric, 1)                            AS avg_total_ms
FROM t_knowledge_document_chunk_log
WHERE create_time >= NOW() - INTERVAL '24 hours';
