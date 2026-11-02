# Ragent 量化评测套件（一键测量）

用于把 `docs/resume-project-experience.md` 里的 `【实测】` 占位替换成**你自己跑出来的真实数字**。

## 产出指标

| 类别 | 指标 |
|---|---|
| 检索质量 | Hit@1 / Hit@3 / Hit@5 / Hit@10、MRR、context_precision、context_recall |
| 意图识别 | 意图 Top-1 准确率 |
| 检索耗时 | `/rag/eval` 的 `latencyMs`：avg / P50 / P95 |
| 运行指标（可选 SQL） | 首包 TTFT、端到端延迟 P50/P95、成功率、错误率、无知识率、慢请求率 |

---

## 方案A 快速开始（Bailian + SiliconFlow）

> 说明：仓库默认路由就是方案A —— 对话/重排/图生文走 `bailian`，向量化走 `siliconflow`。
> 已把未启用的 Ollama（`qwen3-local`、`qwen-emb-local`）和 AIHubMix（`gpt-5.4`、`text-embedding-3-large`）候选设为 `enabled: false`，避免降级链空跑失败重试。需要时把它们改回 `true` 即可。

### 1. 设置 Key

```powershell
# 当前会话有效
$env:BAILIAN_API_KEY="sk-百炼的key"
$env:SILICONFLOW_API_KEY="sk-硅基流动的key"
```

或永久写入用户环境变量（重开终端 / IDE 生效）：

```powershell
[Environment]::SetEnvironmentVariable("BAILIAN_API_KEY","sk-百炼的key","User")
[Environment]::SetEnvironmentVariable("SILICONFLOW_API_KEY","sk-硅基流动的key","User")
```

### 2. 自检 Key 与模型（不启动应用）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\eval\check-providers.ps1
```

会分别打 Bailian Chat(`qwen-plus`)、SiliconFlow Embedding(`Qwen/Qwen3-Embedding-8B`)、Bailian Rerank(`qwen3-rerank`) 三个真实端点，全 `PASS` 再继续。

### 3. 继续下方的「0. 前置条件」

Key 通过后，按顺序准备数据库 / Redis / RocketMQ、导入文档、准备评测集，再跑 `measure-retrieval.ps1`。

---

## 0. 前置条件

1. **服务全部起来**：PostgreSQL(5432, 库 `ragent`，已执行 `schema_pg.sql` + `init_data_pg.sql`)、Redis(6379)、RocketMQ(9876)。
   > pgvector 需要 PG 扩展；若用 Milvus，把 `rag.vector.type` 设为 `milvus`。
2. **模型可用**：设好至少一个 Key（`BAILIAN_API_KEY` 等），或本地装 Ollama 并把 `ai.chat.default-model` / `ai.embedding.default-model` 换成 `qwen3-local` / `qwen-emb-local`。
3. **评测开关**：`application.yaml` 中 `app.eval.enabled: true`（仓库默认已是 true）。
4. **文档已入库**：关键！`t_knowledge_document.doc_name` 去掉扩展名后，必须**正好等于**评测集里的 `reference_doc_ids`（例如文件名叫 `FAQ_VAC_001.pdf` → 业务码 `FAQ_VAC_001`）。这是 `EvalController` 对齐的规则。
5. 启动应用：`.\mvnw.cmd spring-boot:run -pl bootstrap`（端口 9090，context-path `/api/ragent`）。

验证接口通不通：

```powershell
Invoke-RestMethod "http://localhost:9090/api/ragent/rag/eval?question=空调怎么报修" | ConvertTo-Json -Depth 6
```

---

## 1. 准备评测集

复制 `dataset.sample.jsonl` 改成你自己的数据，**JSONL 格式，一行一条**：

```json
{"id":"q001","question":"空调制冷效果差怎么报修？","reference_doc_ids":["FAQ_VAC_001"],"intent_l2":"node_vac_repair","category":"single_intent"}
```

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | 是 | 用例编号 |
| `question` | 是 | 用户问题 |
| `reference_doc_ids` | 否 | 标准相关文档**业务码**数组；为空则该条不计入检索指标（仅计延迟） |
| `intent_l2` | 否 | 标准意图叶子节点 id；为空则不计入意图准确率 |
| `category` | 否 | 分组标签（single_intent / multi_intent / ambiguous / no_answer），便于分组分析 |

建议规模 **≥ 200 条**，分布覆盖：单意图、多意图、近义改写、歧义、无答案。

> 评测前请确认：`/rag/eval?question=...` 返回的 `retrievedDocIds` 里能看到你期望的业务码，否则说明入库文件名没对齐。

---

## 2. 跑一次测量

```powershell
# 默认连 localhost:9090，读 dataset.sample.jsonl
powershell -ExecutionPolicy Bypass -File .\scripts\eval\measure-retrieval.ps1

# 指定数据集 / 带登录 token / 打标签
powershell -ExecutionPolicy Bypass -File .\scripts\eval\measure-retrieval.ps1 `
  -Dataset .\scripts\eval\my-dataset.jsonl `
  -Token "<你的 Sa-Token>" `
  -Label "baseline"
```

输出：

- 控制台汇总表
- `scripts/eval/out/<时间>-<Label>.summary.json`（汇总）
- `scripts/eval/out/<时间>-<Label>.per-query.csv`（逐条明细，便于排查）

### 命令参数

| 参数 | 默认 | 说明 |
|---|---|---|
| `-BaseUrl` | `http://localhost:9090/api/ragent` | 服务地址 |
| `-Dataset` | `dataset.sample.jsonl` | 评测集路径 |
| `-Token` | 空 | 需要鉴权时填 Sa-Token |
| `-Label` | `default` | 结果标签（ablation 时区分） |
| `-OutDir` | `scripts/eval/out` | 输出目录 |
| `-TimeoutSec` | 120 | 单请求超时 |

---

## 3. Ablation：量化「提升 X%」的来源

简历里的提升数字 = **开 / 关某个组件的指标差**。做法：

1. 先用当前完整配置跑：`-Label baseline`。
2. 改 `application.yaml`，**每次只关一个**，重启应用，再跑一次：

   | 对比实验 | 改动 |
   |---|---|
   | 关闭 Rerank | `rag.rerank.enabled: false` |
   | 关闭查询改写 | `rag.query-rewrite.enabled: false` |
   | 关闭意图定向检索 | `rag.search.channels.intent-directed.enabled: false` |

3. 比较两次结果：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\eval\compare-reports.ps1 `
  -Baseline .\scripts\eval\out\<baseline>.summary.json `
  -Variant  .\scripts\eval\out\<no-rerank>.summary.json
```

输出每个指标的 `baseline → variant` 与相对变化百分比。**提升 = (开 - 关) / 关。**

---

## 4. 延迟 / 首包 / 成功率（trace 表）

检索指标不含 LLM 生成。要看首包 TTFT、端到端延迟、成功率，用 `trace-metrics.sql`：

```powershell
psql "postgresql://postgres:postgres@127.0.0.1:5432/ragent" -f .\scripts\eval\trace-metrics.sql
```

或在管理台看现成接口：`GET /api/ragent/admin/dashboard/performance`（返回 avg/p95 延迟、successRate、errorRate、noDocRate、slowRate）。

---

## 5. 限流 / 并发（可选）

用仓库自带脚本做并发压测（首包时间戳由 perl 采集）：

```bash
CONCURRENCY=30 BASE_URL=http://localhost:9090/api/ragent TOKEN=<token> bash scripts/sse_queue_test.sh
```

观察：超过 `rag.rate-limit.global.max-concurrent`(默认 10) 的请求是否排队/被降级，以及开/关限流时上游 429/超时率的差异。

---

## 6. 回填简历

把 `summary.json` 里的数字填到 `docs/resume-project-experience.md` 第一节的量化落款，例如：

> 「在 260 条标注评测集上做 ablation：单路向量检索 Hit@3 = 0.71 → 多路 + Rerank 后 Hit@3 = 0.88（+24%），MRR 0.62 → 0.81（+31%），意图 Top-1 0.90；检索阶段 P95 = 420ms。」

> 注意：报 LLM/延迟类指标时**务必带上样本量**，并优先报 P50/P95 而非均值。
