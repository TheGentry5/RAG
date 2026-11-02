# AGENTS.md — Ragent

企业级 Agentic RAG + AI Agent 平台（Java 17 / Spring Boot 3.5.7）。后端四模块 + React 前端。
Windows 下把下文 `./mvnw` 换成 `.\mvnw.cmd`。

## 快速开始

```bash
# 1) 先安装兄弟模块（framework / infra-ai / mcp-server）
#    只跑 `-pl bootstrap` 时，未安装的本地模块无法从仓库解析，务必先 install
./mvnw -DskipTests install

# 2) 启动后端（9090，context-path: /api/ragent）
./mvnw spring-boot:run -pl bootstrap

# 推荐：本地启动脚本，读取 .env.local 注入 API Key 并自动 install
powershell -ExecutionPolicy Bypass -File .\run-local.ps1

# 编译 / 测试
./mvnw clean compile -DskipTests              # compile 阶段自动 spotless:apply（Apache license header）
./mvnw test -pl bootstrap -Dtest=ClassName    # 跑单个测试
./mvnw test                                   # 需要本地 PostgreSQL / Redis / RocketMQ

# 前端（frontend/）
npm install
npm run dev      # Vite 5173，/api 代理到 localhost:9090
npm run build
npm run lint     # eslint --max-warnings 0，零警告策略
npm run format   # prettier（printWidth 100, singleQuote false, no trailingComma）
```

`.env.local` 已被 gitignore；从 `.env.local.example` 复制，`run-local.ps1` 只把 Key 注入到当前启动进程。
前端没有测试脚本，`npm run lint` 是唯一自动化校验。

## 多模块 Maven 结构

依赖链：`framework` ← `infra-ai` ← `bootstrap`。`mcp-server` 独立。

| 模块 | Java/TS 文件数 | 职责 |
|---|---|---|
| `bootstrap/` | ~415 Java | RAG 流水线、意图、检索、MCP、入库、管理 API（全部业务逻辑） |
| `framework/` | 38 Java | Redis、MyBatis、Sa-Token、RocketMQ、分布式 ID、Trace、TTL |
| `infra-ai/` | 47 Java | Chat/Embedding/Rerank 抽象，多供应商路由 + 三态熔断器 |
| `mcp-server/` | 5 Java | 独立 JSON-RPC 2.0 MCP 服务器（端口 9099） |
| `frontend/` | 89 TS/TSX | React 18 + Vite + Tailwind + shadcn/ui |

`framework`、`infra-ai`、`mcp-server` 是纯 Java 模块，无前端或 Docker 资源目录。

## 架构要点

- **对话入口**：`bootstrap/.../rag/service/impl/RAGChatServiceImpl.streamChat()` → `StreamChatPipeline.execute()`（记忆 → 改写拆分 → 意图解析 → 歧义引导 → 系统响应/检索 → 空结果处理 → Prompt 组装 → 流式输出）
- **多路检索**：`RetrievalEngine` 委托 `MultiChannelRetrievalEngine`，通道并行后经 `SearchResultPostProcessor` 链去重、重排
- **数据库**：PostgreSQL（`resources/database/schema_pg.sql` 中 21 张表）+ pgvector 或 Milvus 2.6.6；切换 `rag.vector.type` = `pg` | `milvus`
- **提示词模板**：`bootstrap/src/main/resources/prompt/*.st`（14 个，`{key}` 占位符）
- **意图树**：3 层（DOMAIN → CATEGORY → TOPIC），存 `t_intent_node` + Redis 缓存
- **限流**：Redis 分布式信号量（ZSET + Pub/Sub + Lua）
- **线程池**：全部用 `TtlExecutors` 包装以传播用户 / Trace 上下文，新增线程池不要裸用 `Executors`
- **MCP**：独立 `mcp-server`，自带 `main()`，通过 `rag.mcp.servers[].url` 接入（默认 `http://localhost:9099`）

## 扩展模式

实现 Spring `@Component` 接口即可自动发现：

| 接口 | 作用 |
|---|---|
| `SearchChannel` | 新增检索通道 |
| `SearchResultPostProcessor` | 后处理器（去重、重排序） |
| `McpToolExecutor`（注意小写 c） | 新增 MCP 工具 |
| `IngestionNode` | 新增入库流水线节点 |
| `ChatClient`（`infra-ai`） | 新增模型供应商 |

## 外部服务

所有服务需要本地实例（默认端口），Docker Compose 文件在 `resources/docker/`：

| 服务 | 端口 | 必选 | 说明 |
|---|---|---|---|
| PostgreSQL | 5432 | 是 | 手动启动；库 `ragent`，执行 `schema_pg.sql` + `init_data_pg.sql`；用户/密码默认 `postgres`/`postgres` |
| Redis | 6379 | 是 | 手动启动，密码 `123456` |
| RocketMQ | 9876 | 是 | `rocketmq-stack-5.2.0.compose.yaml`（AMD64 用 `rocketmq-stack-amd-5.2.0.compose.yaml`） |
| Milvus | 19530 | 可选 | `milvus-stack-2.6.6.compose.yaml`；轻量版在 `lightweight/`（含 2.5.8 降级版） |
| RustFS | 9000 | 可选 | 随 Milvus stack 启动（`rustfsadmin`/`rustfsadmin`） |
| MinerU SaaS | — | 可选 | 高级 PDF 解析，需 `MINERU_API_KEY` |

**PostgreSQL 端口注意**：仓库默认 `5432`，但当前工作区的 `application.yaml` 被本地改为 `15432`（Windows 保留端口段）。连库前先看 `spring.datasource.url`，不要硬编码 5432。

## 模型供应商

在 `bootstrap/src/main/resources/application.yaml` 的 `ai.providers` 和 `ai.chat.candidates` 中配置：

| 供应商 | 环境变量 | 模型示例 |
|---|---|---|
| 阿里百炼 | `BAILIAN_API_KEY` | qwen-plus, qwen3-max |
| siliconflow | `SILICONFLOW_API_KEY` | Qwen/Qwen3-Embedding-8B |
| aihubmix | `AIHUBMIX_API_KEY` | gpt-5.4（默认 disabled） |
| ollama | —（本地） | qwen3:8b-fp16（默认 disabled） |

默认对话 `qwen-plus`，默认 Embedding `qwen-emb-8b`（1536 维）。`scripts/eval/README.md` 有量化评测流程和 `check-providers.ps1` 自检脚本。

## 风格与约定

- **Lombok**：广泛使用；`lombok.config` 启用 `@Generated`（JaCoCo 忽略），`@Qualifier` 可复制到构造参数
- **Spotless**：`mvn compile` 自动修改源码加 Apache 2.0 header，不要手工删
- **ID**：Snowflake 生成，数据库统一 `VARCHAR(20)`
- **逻辑删除**：每张表 `deleted`（SMALLINT 0/1）和 `update_time`
- **数据库升级**：`resources/database/upgrade_v1.0_to_v1.1.sql`、`upgrade_v1.1_to_v1.2.sql`
- **前端 `@/` 别名**：TS `@/*` → `src/*`（`tsconfig.app.json` + `vite.config.ts`）
- **shadcn/ui**：组件物理存放在 `frontend/@/components/ui/`（不是 `src/components/ui`）

## 测试注意事项

- **Mockito**：`bootstrap/src/test/resources/mockito-extensions/org.mockito.plugins.MockMaker` 内容为 `mock-maker-subclass`；根 pom surefire 通过 `-javaagent:${org.mockito:mockito-core:jar}` 添加支持
- **`application-test.yaml` 不在仓库中**，需本地创建
- **`@SpringBootTest` 测试**（如 `PgVectorStoreServiceTest`）需要本地 PostgreSQL、Redis、RocketMQ 全起
- **MinerU 集成测试**（`MinerUPdfUploadFlowTest`）：默认跳过，需 `-Dmineru.test.pdf=/path/to/file.pdf` + `MINERU_API_KEY` + 全部外部服务
- **SSE 压测脚本**：`scripts/sse_queue_test.sh`，依赖 `BASE_URL`、`TOKEN` 等环境变量
- **评测套件**：`scripts/eval/`（PowerShell，需先启动应用并完成文档入库）

## 文档可信度

以代码和配置文件为准。`docs/quick-start.md` 与 `frontend/TESTING.md` 有过期内容（如 `application-search.yml`、后端 8080），不要直接照抄。

## 关键配置速查

```yaml
# bootstrap/src/main/resources/application.yaml
server.port: 9090
server.servlet.context-path: /api/ragent
spring.datasource.url: jdbc:postgresql://127.0.0.1:15432/ragent   # 本地改动；仓库默认为 5432
spring.datasource.username: postgres
spring.datasource.password: postgres
spring.data.redis.password: 123456
rocketmq.name-server: 127.0.0.1:9876
rag.vector.type: pg    # pg | milvus
rag.default.dimension: 1536
```
