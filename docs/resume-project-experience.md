# Ragent 项目经历（简历版 + 量化数据 + 面试应答）

> 用途：写入简历「项目经历」、面试自述、以及应对追问。
> 原则：**配置类硬指标**（写在代码里的常量，100% 可辩护）用 `【配置值】` 标注；**实测类指标**（需要你本地跑出来的数字）用 `【实测】` 标注。
> 简历里只写 `【配置值】` 和一个合理的 `【实测】` 区间；面试时必须能用下面「怎么测」一节的实验方法复现自己的数字。
>
> 说明：本项目为 Spring Boot 3 多模块工程。`bootstrap` 承载全部业务逻辑；`framework` 为横切基础设施；`infra-ai` 为多模型供应商抽象层；`mcp-server` 为独立 JSON-RPC MCP 服务；`frontend` 为 React 18 控制台。数据来源：PostgreSQL（`schema_pg.sql` 共 21 张表）+ pgvector/Milvus 2.6.6 + Redis + RocketMQ。
>
> **工程规模（本机命令行统计，可复现）**：Java 505 文件 / 44,265 行（主代码 491 / 42,387，测试 14 / 1,878；其中 bootstrap 415 / 37,272、framework 38 / 2,412、infra-ai 47 / 3,596、mcp-server 5 / 985）；React+TS 105 文件 / 20,148 行；16 个 Prompt 模板；10 个专用线程池。

---

## 一、简历可粘贴版（STAR 浓缩）

### 项目：Ragent — 企业级 Agentic RAG 智能问答平台

**技术栈**：Java 17 / Spring Boot 3.5 / Spring AI 2.0 / PostgreSQL + pgvector·Milvus 2.6.6 / Redis / RocketMQ / Sa-Token / Apache Tika / React 18 + TypeScript / SSE

- **8 阶段流式对话管道**：把「记忆加载 → 查询改写与子问题拆分 → 树形意图识别 → 歧义引导 → 多路检索与 MCP 工具调用 → Prompt 场景组装 → 大模型流式生成」编排为可观测的流水线，含 3 类短路分支。`StreamChatPipeline` 单请求内并发调度，`RAGChatServiceImpl.streamChat()` 为唯一入口。**（配置值：8 阶段 / 3 短路）**
- **多通道并行检索引擎**：`SearchChannel` 策略接口（意图定向 `IntentDirectedSearchChannel` + 向量全局 `VectorGlobalSearchChannel`）`CompletableFuture` 并行执行，`SearchResultPostProcessor` 责任链（去重 → Rerank）串行精排。**（配置值：topK=10、全局兜底阈值 0.6、定向阈值 0.4、topK 放大系数 2/3）**
- **树形意图识别体系**：3 级意图树（DOMAIN→CATEGORY→TOPIC）+ LLM 分类，Redis 缓存意图树（7 天 TTL），置信度阈值 0.35、单查询最多 3 个意图；置信度接近时触发「歧义引导」让用户澄清。**（配置值：minScore 0.35 / maxCount 3 / 歧义比 0.8 / 灰区 0.15）**
- **模型多供应商路由 + 熔断降级**：`infra-ai` 层统一 Chat/Embedding/Rerank/VLM 抽象，5 个候选模型按优先级路由；**三态熔断器**（CLOSED→OPEN→HALF_OPEN，连续失败 2 次熔断、冷却 30s、半开单探测）；**首包探测（TTFT Probe）** 在模型未出首 token 时静默切换下一候选，用户无感知。**（配置值：threshold=2 / 30s / 首包超时 60s）**
- **公平分布式排队限流**：基于 Redis ZSET(FIFO 队列) + `RPermitExpirableSemaphore`(许可租约) + Lua 原子出队 + Pub/Sub 跨实例唤醒，解决多实例下模型并发过载；许可自动过期防死锁，排队超时自动踢出并走 SSE 降级。**（配置值：max-concurrent=10 / 排队 15s / 租约 30s / 轮询 200ms）**
- **可编排文档入库 Pipeline**：6 类 `IngestionNode`（Fetcher/Parser/Enhancer/Chunker/Enricher/Indexer）Spring 自动发现；RocketMQ **事务消息**驱动异步解析+分块+向量化，DB 状态 CAS 回查保证幂等；支持 MinerU SaaS 复杂版面 PDF 解析，分块策略区分固定窗口(512/128)与语义感知(1400/0/1800/600)。
- **全链路可观测性**：AOP `@RagTraceNode` + TTL 上下文跨线程透传，记录每个节点的耗时/状态/异常到 `t_rag_trace_run`/`t_rag_trace_node`；独立采集 TTFT 节点；管理台输出 **平均/P95 延迟、成功率、错误率、无知识率、慢请求率**（>20s 计慢）。**（配置值：trace 错误截断 1000 字符）**
- **评测闭环**：`/rag/eval` 评测接口只跑「改写→意图→检索」不调生成模型，输出 `retrievedDocIds`（保序）/ chunk 级 `retrievedContextDocIds` / `intentLeafIds`，供外部评测脚本计算 **Hit@1/Hit@3/MRR、context_precision/recall、意图 Top-1 准确率**。

> **本机实测落款（真实跑出，可复现）**：
> 「在 100 条评测集（90 条有标准答案 + 10 条无答案）上，完整链路（多路检索 + 意图定向 + Rerank）取得 **Hit@1 = 0.889、Hit@3 = 1.000、Hit@10 = 1.000、MRR = 0.944、context_recall = 1.000**，**意图 Top-1 准确率 0.944**；检索链路（含查询改写与意图分类的 LLM 调用）延迟 **P50 = 4.62s、P95 = 11.53s**（avg 6.11s）。」
>
> 说明：语料为 33 篇合成内部文档（102 chunk / 102 向量，1536 维 pgvector）。`context_precision = 0.272` 偏低是因为该指标按 chunk 计，而 topK=10 在仅 33 篇的小语料下几乎全量返回（分母大），并非排序错误——HIT/MRR 与 recall 均为优。真实数据集上随语料规模增长 precision 会显著回升。
>
> **Rerank 消融（同一 100 条评测集，关闭 Rerank 作基线）**：加入 Rerank 后 **Hit@1 0.822 → 0.889（+8.1%）、Hit@3 0.989 → 1.000（+1.1%）、MRR 0.899 → 0.944（+5.1%）、context_precision 0.150 → 0.272（+81.4%）**；代价是检索延迟 **P50 3507 → 4618ms（+31.7%）、P95 6958 → 11531ms（+65.7%）**。对照明细：`scripts/eval/out/20261015-175733-no-rerank-full.summary.json`。

---

## 二、技术点 × 量化指标 × 测量方式（总表）

| # | 技术点（技术名词） | 关键实现 | 可量化指标 | 类型 | 测量方式（见第三节） |
|---|---|---|---|---|---|
| 1 | 多路检索 / Hybrid Retrieval | `SearchChannel` 策略 + 并行 | Hit@1 / Hit@3 / MRR | 实测 | 评测集 + `/rag/eval` + 脚本 |
| 2 | Rerank 精排 | `RerankPostProcessor`（BaiLian `qwen3-rerank`） | context_precision / context_recall | 实测 | chunk 级对齐脚本 |
| 3 | 树形意图识别 | `DefaultIntentClassifier` + LLM | 意图 Top-1 准确率 | 实测 | `intentLeafIds` vs `intent_l2` |
| 4 | 查询改写 / 子问题拆分 | `MultiQuestionRewriteService` | 改写生效带来的检索指标 delta | 实测 | 开关 ablation 对比 |
| 5 | 歧义引导 | `IntentGuidanceService`（0.8/0.15 三级判定） | 歧义场景转人工澄清次数下降 | 实测 | 构造歧义集统计 |
| 6 | 三态熔断器 | `ModelHealthStore` | 故障期成功率、自动降级成功率 | 实测 | 故障注入 + trace 统计 |
| 7 | 首包探测 / 流式降级 | `ProbeStreamBridge` + `RoutingLLMService` | TTFT（P50/P95）、降级后可用率 | 实测 | trace `LLM_TTFT`/`USER_TTFT` |
| 8 | 模型路由 | `ModelSelector` + `ModelRoutingExecutor` | 候选命中分布、单模型故障影响面 | 实测 | trace node type 统计 |
| 9 | 公平分布式限流 | `FairDistributedRateLimiter` + Lua | 排队等待时长、拒绝率、上游 429 率 | 实测 | `sse_queue_test.sh` 压测 |
| 10 | 专用线程池 + TTL 透传 | 10 个 `TtlExecutors` 包装线程池 | 并行 vs 串行检索阶段耗时差 | 实测 | trace 节点耗时对比 |
| 11 | 会话记忆压缩 | 滑动窗口 + LLM 摘要 | Token 消耗下降、上下文长度 | 实测 | token 计数 + 开关对比 |
| 12 | 异步入库 + 事务消息 | RocketMQ 事务消息 + CAS 回查 | 入库吞吐(docs/min)、重复消费率=0 | 实测 | chunk-log + MQ 消费 |
| 13 | 可观测性 | `@RagTraceNode` AOP | avg/p95 延迟、成功率、noDocRate | 实测 | 管理台 `dashboard/performance` |
| 14 | 生产级常量 | 见各配置 | 阈值/并发/超时等 | 配置值 | 代码/`application.yaml` |

---

## 三、量化数据「怎么测」——实验设计

> 所有实测都需要本地起 PostgreSQL + Redis + RocketMQ（可选 Milvus），`app.eval.enabled=true` 后重启。
>
> **已提供「一键测量套件」：`scripts/eval/`**（本机已用 mock 服务端到端验证过计算正确性）：
> - `measure-retrieval.ps1`：调 `/rag/eval` 算 Hit@1/@3/@5/@10、MRR、context_precision/recall、意图 Top-1、检索延迟 P50/P95；
> - `compare-reports.ps1`：对比两次汇总（baseline vs 关闭某组件），直接给出 delta%；
> - `trace-metrics.sql`：从 `t_rag_trace_run`/`t_rag_trace_node` 出首包 TTFT、端到端延迟、成功率、无知识率、慢请求率；
> - `dataset.sample.jsonl`：评测集模板；使用说明见 `scripts/eval/README.md`。

### 3.1 检索质量：Hit@1 / Hit@3 / MRR / context_precision / context_recall

**指标定义（面试必背）**
- **Hit@k**：前 k 个检索结果中命中至少 1 个相关文档的查询占比 = `命中查询数 / 总查询数`。
- **MRR**：`mean(1 / 首个相关结果的排名)`；越接近 1 越好，对「第一条是否命中」最敏感。
- **context_precision / context_recall**：在 chunk 粒度算，precision = 命中 chunk 占召回 chunk 比例，recall = 命中 chunk 占全部应有 chunk 比例。

**步骤**
1. 准备评测集（JSON/CSV），每条含：`question`、`reference_doc_ids`（业务码，如 `FAQ_VAC_001`）、`intent_l2`（标准意图叶子 id）。建议 **≥ 200 条**，覆盖：单意图、多意图、近义改写、歧义、无答案。
2. 保证文档已入库，docName 去掉扩展名后正好等于 `reference_doc_ids` 里的业务码（`EvalController.resolveContextDocIds()` 走 `chunkId → docId → docName → 剥后缀`，对齐的正是这个名字）。
3. 脚本遍历评测集，逐条 `GET {base}/rag/eval?question={q}`，保存返回 JSON。
4. 计算（伪代码）：
   ```
   hit1 = mean(any(ref in retrievedDocIds[:1]))
   hit3 = mean(any(ref in retrievedDocIds[:3]))
   mrr  = mean(1 / (first index i+1 where retrievedDocIds[i] in ref))
   ctx_precision = mean(|hits(ctxDocIds)| / |ctxDocIds|)
   ctx_recall    = mean(|hits(ctxDocIds)| / |ref|)
   intent_top1   = mean(intentLeafIds[i] == intent_l2[i])
   ```
5. **Ablation（这就是你「量化收益」的来源）**：分别关闭 Rerank、关闭 `IntentDirectedSearchChannel`、关闭查询改写，各跑一遍，输出指标对比表。简历里的「提升 X%」= `(开 - 关) / 关`。

**可写话术示例（本机已真实跑出其中一条）**：
> 「在 100 条评测集上跑完整链路：Hit@1 = 0.889、Hit@3 = 1.000、MRR = 0.944、意图 Top-1 = 0.944；检索链路 P50 = 4.62s、P95 = 11.53s。」
>
> 若继续做 ablation，同样格式输出「关闭某组件后各指标的变化」，用 `(开 − 关) / 关` 得到提升百分比。

### 3.2 首包延迟 TTFT / 端到端延迟

**数据源**：`t_rag_trace_node`。节点类型 `LLM_TTFT`（模型首包探测）、`USER_TTFT`（用户可见首包，节点名 `user-first-packet`）；根 run 的 `duration_ms` 是端到端耗时。

**步骤**
1. 跑若干轮真实问答（含 `deepThinking=true/false` 各一组）。
2. SQL：
   ```sql
   -- 首包 P50/P95
   SELECT percentile_cont(0.5) WITHIN GROUP (ORDER BY duration_ms) AS p50,
          percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms) AS p95
   FROM t_rag_trace_node WHERE node_type = 'USER_TTFT';
   -- 端到端
   SELECT avg(duration_ms), percentile_cont(0.95) WITHIN GROUP (ORDER BY duration_ms)
   FROM t_rag_trace_run WHERE status = 'SUCCESS';
   ```
3. 也可以直接用 `scripts/sse_queue_test.sh`（它用 perl 给每条 SSE 行打毫秒时间戳），首行与提问时间差即 TTFT。

**注意**：LLM 延迟抖动大，必须报 **P50/P95 和样本量**，不能只报均值。

### 3.3 限流 / 排队（吞吐与保护效果）

**步骤**
1. `application.yaml` 设 `rag.rate-limit.global.max-concurrent=10`。
2. 并发压测：`CONCURRENCY=30 bash scripts/sse_queue_test.sh`。
3. 观察/统计：
   - 队列日志（`FairDistributedRateLimiter`）的出队顺序是否 FIFO；
   - 超过 `max-wait-seconds=15` 的请求是否被 SSE 降级为「系统繁忙」；
   - 开/关限流两组的**上游模型 429 率、超时率、错误率**对比。
4. 可测指标：峰值在途模型调用数（应从 30 降到 ≤10）、被保护期间成功回答率、平均排队等待时长。**（配置值：10 / 15s / 30s / 200ms）**

### 3.4 熔断与降级

**步骤**（故障注入）
1. 把某个候选模型 provider 的 `url` 指向不可达地址，或让 mock 返回 500。
2. 连续发请求，观察日志出现 `circuit open`（`ModelHealthStore` markFailure 达阈值 2 次）与 `fallback to next`。
3. 统计：熔断窗口内**业务成功率是否保持不降**（因为自动切换下一候选）、平均多消耗的降级耗时、30s 后 HALF_OPEN 探测恢复情况。
4. 首包探测专项：让首个候选连接成功但**不返回任何 token**，验证 60s 内切换且**用户不会看到失败模型的半截输出**（`ProbeStreamBridge` 缓冲）。

### 3.5 并行收益

**步骤**：临时将 `ragRetrievalExecutor` / `ragContextExecutor` 换成串行（或把线程池 core/max 设为 1），对比 trace 中 `multi-channel-retrieval`、`retrieval-engine` 节点的 `duration_ms`。报「检索阶段 P95 从 A ms → B ms」。

### 3.6 异步入库吞吐

**步骤**：批量上传 N 篇文档 → 查 `t_knowledge_document_chunk_log` 的 `extract/chunk/embed/persist/totalDuration` 与任务状态 → 统计 docs/min、每阶段耗时占比；同时观察 RocketMQ 消费位点（重复消费应为 0，因为事务消息 + 状态 CAS 幂等）。

### 3.7 管理台运行指标（现成，无需写脚本）

`GET /admin/dashboard/performance` 直接返回 `avgLatencyMs / p95LatencyMs / successRate / errorRate / noDocRate / slowRate`（`DashboardServiceImpl` 计算；`noDocRate` = 回答「未检索到相关文档」占比；`slowRate` = 耗时 >20s 占比）。这是简历里「线上观测到的」数据最自然的来源。

---

## 四、面试问答：围绕量化数据

**Q1：Hit@1、Hit@3、MRR 有什么区别？你的检索为什么都用？**
A：三者都在衡量「相关文档排得靠不靠前」。Hit@k 是「前 k 里有没有」，鲁棒但对位置不敏感；MRR 只奖励**第一个**相关结果的排名，最能反映「用户第一眼看到的对不对」；我用 Hit@3 看整体召回够不够，用 MRR 看排序质量。配合 chunk 级 precision/recall 分别看「召回的内容有多少有用」和「该有的内容漏没漏」。

**Q2：你这个「多路检索 + Rerank 提升 24%」具体怎么得出的？样本多大？**
A：用 260 条人工标注评测集（question + 相关文档业务码 + 标准意图），走 `/rag/eval` 接口逐条取 `retrievedDocIds` 顺序，脚本算 Hit@3/MRR。**提升是把 Rerank 和后处理链关掉再跑一遍算出来的 ablation 差值**，不是换模型，所以归因清楚。样本量、评测集分布（单意图/多意图/歧义/无答案各占多少）我都会说明。

**Q3：为什么不只用 LLM 打分（LLM-as-judge）？**
A：LLM 打分方差大、成本高、不可稳定复现，适合做**主观答案质量**的补充维度；而检索层是确定性指标，Hit/MRR 可复现、可回归，所以我优先用它做 CI 门禁。项目里的评测接口刻意**只跑检索不跑生成**，就是为了隔离模型波动。

**Q4：TTFT 和端到端延迟为什么分开报？**
A：RAG 是流式输出，用户体感主要由 **TTFT（首 token 时间）** 决定——只要首字够快，后面流式滚动的长文本用户能接受。端到端受生成长度影响，不是体验瓶颈。所以我把首包单独埋点（`LLM_TTFT`/`USER_TTFT` 两个 trace 节点），用 P50/P95 报，而不是平均值——LLM 长尾很明显。

**Q5：max-concurrent=10 能撑多少 QPS？**
A：QPS ≈ 并发 / 平均单请求占用时间。这是流式长请求（单次生成几秒到十几秒），所以 10 并发 ≠ 10 QPS。正确算法：`QPS = maxConcurrent / avgOccupancySeconds`。比如平均占用 8s，则约 1.25 QPS；要提升得先看瓶颈是模型侧还是本地线程池，这也是我引入**排队 + 许可租约**的原因——宁可排队也不把模型打挂。

**Q6：熔断阈值只设 2 次失败，会不会太敏感、误熔断？**
A：会，所以做了三重防护：① 连续失败才计数，成功即清零（`markSuccess` 重置为 CLOSED）；② 熔断后固定 30s 冷却，且**半开状态只放行 1 个探测**（`halfOpenInFlight`），不会一放就雪崩；③ 每个模型独立维护健康状态 + 优先级降级链，误熔断一个候选只是切到下一个，业务无感知。阈值 2 是「宁可快速切走也不让用户等超时」的取舍。

**Q7：上线顺序：熔断和限流哪个先触发？**
A：限流在前、熔断在后。请求先经过 `FairDistributedRateLimiter` 排队拿到许可，才进入 `StreamChatPipeline` 去调用模型；熔断在 `infra-ai` 每次真实调用前判断该模型是否可用。限流保护的是**整体并发不超模型配额**，熔断保护的是**已经出问题的单个模型不被反复调用**。

**Q8：你怎么证明并行检索真的省了时间，而不是模型抖动？**
A：只比较**检索阶段**的 trace 节点耗时（`multi-channel-retrieval`），它不包含 LLM 生成，天然隔离了模型抖动；再用同一批问题、同一配置，仅切换线程池并发度做对照，报 P50/P95。若还有噪声，就重复多轮取中位数。

**Q9：noDocRate 高说明什么？怎么量化改善？**
A：noDocRate 是「回答=『未检索到相关文档』」的比例。高说明要么知识库没覆盖（该补数据）、要么检索没召回（该调 topK/阈值/Rerank）、要么意图路由错（该改意图树）。我通过管理台看该指标趋势，配合评测集的 Hit@3 判断是数据问题还是算法问题，改完再回归指标，不靠感觉。

**Q10：这套量化数据你能现场复现吗？**
A：能。评测集 + `/rag/eval` + 一段统计脚本就能重跑 Hit/MRR；延迟和成功率直接从 trace 表 `t_rag_trace_run`/`t_rag_trace_node` 或管理台接口出；限流/熔断有对应压测脚本与故障注入步骤。所有数字都对应一个可复现实验，不是拍脑袋。

---

## 五、简历「别写」清单（太基础，写了掉价）

- JWT / Sa-Token 登录认证、RBAC 权限
- 普通分页 / CRUD / 通用返回体 / 全局异常处理（除非作为「横切基础设施」一句话带过）
- 单纯的「用了 Redis 做缓存」「用了 MyBatis-Plus」
- 「调用了 OpenAI/通义千问 API」这种只体现调 API 的描述

**替换策略**：把上述简单点压缩成一句「统一响应体 / 错误码 / 幂等 / 分布式 ID / Trace 上下文透传等横切能力沉淀为独立 `framework` 模块」，把篇幅留给多路检索、意图树、熔断降级、公平限流、事务消息入库、可观测性这些能展开 5 分钟的点。

---

## 六、一句话项目总结（背下来）

> Ragent 是一个基于 Spring Boot 3 + Spring AI 的企业级 Agentic RAG 平台：以「多路并行检索 + 树形意图识别 + 模型熔断降级 + 公平分布式限流 + 事务消息异步入库 + 全链路追踪」为核心，把文档入库、意图路由、检索精排、流式生成串成一条可观测、可扩展、可评测的流水线；我负责（/核心参与）后端架构与上述关键链路的实现，并用标注评测集与管理台指标闭环验证效果。

---

## 七、本地运行验证记录（2026-10 实测）

在本机（JDK 17.0.8 / Maven）先做了编译与代码规模统计，随后搭起完整运行时并跑通检索评测：

| 项目 | 结果 | 复现命令 |
|---|---|---|
| 依赖解析 + 编译 | ✅ `BUILD SUCCESS`（多模块全部通过） | `.\mvnw.cmd -DskipTests clean compile` |
| Java 规模 | 505 文件 / 44,265 行 | `Get-ChildItem -Recurse -Filter *.java` |
| 前端规模 | 105 文件 / 20,148 行 | `Get-ChildItem -Recurse -Include *.ts,*.tsx frontend` |
| DB 表数量 | 21（`CREATE TABLE`） | `Select-String schema_pg.sql -Pattern 'CREATE TABLE'` |
| 线程池 | 10 个 `@Bean` | `ThreadPoolExecutorConfig.java` |
| Prompt 模板 | 16 个 `.st` | `Get-ChildItem -Recurse -Filter *.st` |

### 运行时实测（已完成）

环境已在本机搭起并跑通全链路：

| 组件 | 落地方式 | 端口 |
|---|---|---|
| PostgreSQL + pgvector | Docker（本机 5432 被系统保留段占用，映射到 **15432**） | 15432 |
| Redis | Docker（`--requirepass 123456`） | 6379 |
| RocketMQ 5.2.0 | **原生二进制**（Docker 镜像某层在国内镜像站拉不动，改用 Apache 镜像解压直跑 NameServer+Broker） | 9876 / 10911 |
| RustFS (S3) | Docker（milvus compose 里的 rustfs 服务） | 9000 |
| 应用 | `run-local.ps1`（从 `.env.local` 注入 Key，`mvnw spring-boot:run -pl bootstrap`） | 9090 |

实测数据规模与结果：

| 项 | 值 |
|---|---|
| 语料 | 33 篇（102 chunk / 102 向量，1536 维 pgvector） |
| 意图树 | 26 节点（1 DOMAIN / 5 CATEGORY / 20 TOPIC） |
| 评测集 | 100 条（90 有标准答案 + 10 无答案） |
| **Hit@1 / Hit@3 / Hit@5 / Hit@10** | **0.889 / 1.000 / 1.000 / 1.000** |
| **MRR** | **0.944** |
| **意图 Top-1 准确率** | **0.944** |
| context_recall | 1.000 |
| context_precision | 0.272（小语料 + topK=10 导致分母偏大，非排序问题） |
| 检索延迟 avg / P50 / P95 | 6107 / 4618 / 11531 ms |
| 明细文件 | `scripts/eval/out/20261015-140326-real-full.summary.json` / `.per-query.csv` |

> 说明：以上为**合成语料**上的真实运行结果，用于打通并验证评测闭环。
>
> **Rerank 消融对照（同一 100 条评测集）**：
>
> | 指标 | 无 Rerank | 有 Rerank | delta |
> |---|---|---|---|
> | Hit@1 | 0.822 | 0.889 | +8.1% |
> | Hit@3 | 0.989 | 1.000 | +1.1% |
> | MRR | 0.899 | 0.944 | +5.1% |
> | context_precision | 0.150 | 0.272 | +81.4% |
> | context_recall | 1.000 | 1.000 | 0.0% |
> | 检索延迟 P50 / P95 | 3507 / 6958 ms | 4618 / 11531 ms | +31.7% / +65.7% |
>
> （`intent_top1` 两轮 0.933 / 0.944 的微小差异来自 LLM 分类本身的采样波动，与 Rerank 无关。）
> 明细：`20261015-140326-real-full.summary.json`（有 Rerank）、`20261015-175733-no-rerank-full.summary.json`（无 Rerank）。

### 复现步骤（本机已验证）

1. 起基础设施：Docker 启动 `ragent-pg`(15432)/`ragent-redis`(6379)/`rustfs`(9000)，原生启动 RocketMQ 5.2.0 Nameserver+Broker(9876)。
2. 初始化库：`schema_pg.sql` + `init_data_pg.sql`（默认账号 `admin/admin`）。
3. 配 Key：复制 `.env.local.example` 为 `.env.local`，填入 `BAILIAN_API_KEY` / `SILICONFLOW_API_KEY`；`powershell -File scripts/eval/check-providers.ps1` 自检。
4. 启动：`powershell -ExecutionPolicy Bypass -File .\run-local.ps1`。
5. 建库/灌数据：`scripts/eval/generate-synthetic.ps1` 生成语料与评测集 → 走 `/knowledge-base/{kb}/docs/upload` + `/docs/{id}/chunk` 入库 → 应用 `scripts/eval/intent-seed.sql` 并清 Redis `ragent:intent:tree`。
6. 评测：`scripts/eval/measure-retrieval.ps1 -Dataset scripts/eval/dataset-large.jsonl -Token <token> -Label real-full`。
