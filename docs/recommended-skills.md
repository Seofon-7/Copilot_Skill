# 值得導入的 Agent Skills 推薦清單

> 調查日期：2026-10-13
>
> 調查方式：實際下載各來源的 repo，逐一閱讀 `SKILL.md`、附屬檔案與授權檔，再依 CIM 課的工作內容挑選。主要情境是 C#/.NET、SQL、Windows 桌面程式，以及 code review 與除錯。
>
> 公開 skill 更新很快，導入前請再看一次上游的最新版本。

---

## 1. 結論

- **以 .NET 官方的 `dotnet/skills` 為主力**。它由 .NET 團隊維護、MIT 授權、有公開的評測儀表板，內容最貼近我們的 C# 開發。
- **SQL 相關從 `github/awesome-copilot` 挑**。特別是「改 table 或預存程序前的影響分析」，對舊系統非常實用。
- **工作方法類從 `obra/superpowers` 挑個別 skill**，例如系統化除錯、完成前驗證。不要整包裝。
- **不要導入 `anthropics/skills` 裡的 docx / pdf / pptx / xlsx**。這四個授權禁止複製與散佈到 Anthropic 服務以外。
- **導入方式**：複製到我們的共用 repo，改成 `cim-` 前綴，保留授權檔並記錄來源，再走 MR 審核與 beta 試用（見第 7 章）。

---

## 2. 主要來源一覽

| 來源 | 維護者 | 授權 | skill 數 | 適合度 | 說明 |
|---|---|---|---|---|---|
| [dotnet/skills](https://github.com/dotnet/skills) | .NET 官方團隊 | MIT | 103 | ★★★ | 測試、重構、效能診斷、MSBuild、升級、WinForms；有[評測儀表板](https://dotnet.github.io/skills/)公開每個 skill 的觸發率與效果 |
| [github/awesome-copilot](https://github.com/github/awesome-copilot) | GitHub 社群 | MIT | 427 | ★★ | 數量最多但品質參差；SQL、C# 測試框架、文件類有好用的 |
| [obra/superpowers](https://github.com/obra/superpowers) | 社群 | MIT | 15 | ★★ | 開發方法論（除錯、TDD、code review）；部分 skill 依賴 Claude Code 的功能 |
| [anthropics/skills](https://github.com/anthropics/skills) | Anthropic | 多數 Apache 2.0；docx/pdf/pptx/xlsx 為專有授權 | 19 | ★ | 只建議參考 `skill-creator`（寫 skill 的方法） |
| [trailofbits/skills](https://github.com/trailofbits/skills) | Trail of Bits（資安公司） | CC BY-SA 4.0 | 85 | ★ | 深度資安審查、fuzzing、智慧合約；一般開發用不太到 |
| [microsoft/skills](https://github.com/microsoft/skills) | Microsoft | MIT | 210 | 視情況 | 以 Azure SDK 和 AI Foundry 為主；沒用 Azure 就不需要 |
| [github/copilot-plugins](https://github.com/github/copilot-plugins) | GitHub 官方 | MIT | 2 | — | 目前內容很少（C++ 建置效能、網頁範本） |

---

## 3. 第一批推薦（建議直接導入）

這 10 個和 CIM 課日常工作最相關，而且內容不依賴特定工具，在 Copilot 上可以直接用。

| # | 導入後名稱 | 原始 skill | 來源 | 解決什麼問題 |
|---|---|---|---|---|
| 1 | `cim-run-tests` | `run-tests` | dotnet/skills（dotnet-test） | 讓 Copilot 下正確的 `dotnet test` 指令與篩選條件，不再亂猜參數 |
| 2 | `cim-code-testing` | `code-testing` | dotnet/skills（dotnet-test） | 幫既有程式補單元測試、修失敗的測試，支援 xUnit / MSTest / NUnit |
| 3 | `cim-test-anti-patterns` | `test-anti-patterns` | dotnet/skills（dotnet-test） | 檢查「沒驗證任何東西」、吞例外、順序相依等壞測試，依嚴重度列出 |
| 4 | `cim-csharp-refactoring` | `csharp-refactoring` | dotnet/skills（dotnet） | 安全重構：改名、抽方法、拆類別，強調不改變行為 |
| 5 | `cim-dotnet-performance` | `analyzing-dotnet-performance` | dotnet/skills（dotnet-diag） | 掃描約 50 種效能反模式（async、記憶體、字串、LINQ、I/O），依嚴重度分級 |
| 6 | `cim-sql-code-review` | `sql-code-review` | awesome-copilot | SQL 的安全與品質審查，涵蓋 SQL Server、Oracle 等 |
| 7 | `cim-sql-impact-analysis` | `sql-object-impact-analysis` | awesome-copilot | **改 table、欄位、預存程序前**，追出所有參照它的 SQL 物件與程式碼；舊系統必備 |
| 8 | `cim-csharp-async` | `csharp-async` | awesome-copilot | C# async/await 最佳實務（內容短，可和 `cim-csharp-coding-standard` 互補或合併） |
| 9 | `cim-systematic-debugging` | `systematic-debugging` | superpowers | 先找根因再修，避免「試試看改這裡」的亂槍打鳥 |
| 10 | `cim-verification-before-completion` | `verification-before-completion` | superpowers | 宣稱「修好了」之前，一定要先跑測試或驗證指令 |

**導入時要注意的細節**：

- `code-testing` 內有兩處提到「委派給子代理（subagent）」的流程，Copilot 沒有對應功能時這段沒有作用，導入時可以刪掉。
- `systematic-debugging` 附帶 `.sh` 和 `.ts` 範例腳本，Windows 上需要 Git Bash 或 Node 才能執行。只保留說明文件也可以。
- 我們現有的 `cim-code-review` 可以吸收 #3、#6 的檢查項目，避免功能重疊的 skill 太多，讓 Copilot 不知道該用哪一個。

---

## 4. 依專案需要（第二批）

| 情境 | 原始 skill | 來源 | 用途 |
|---|---|---|---|
| **舊系統現代化** | `thread-abort-migration` | dotnet/skills | 把 .NET Framework 的 `Thread.Abort` 改成 CancellationToken |
| | `migrate-nullable-references` | dotnet/skills | 逐步開啟 nullable reference types 並清掉警告 |
| | `migrate-dotnet8-to-dotnet9` 等 | dotnet/skills | 各版本 .NET 升級與 breaking change 處理 |
| | `dotnet-upgrade` | awesome-copilot | .NET Framework 升級分析的提示集 |
| **桌面程式** | `winforms-expert` | dotnet/skills | WinForms 的建立、修改、除錯、審查（含 Designer 檔） |
| **資料存取** | `optimizing-ef-core-queries` | dotnet/skills | EF Core 查詢效能與正確性審查 |
| | `sql-optimization` | awesome-copilot | SQL 查詢調校與索引建議 |
| | `sql-server-table-reconciliation` | awesome-copilot | 跨環境比對 SQL Server 資料表（遷移、ETL 驗證） |
| **時間與時區** | `dotnet-timezone` | awesome-copilot | `DateTimeOffset`、UTC 轉換、夏令時間；跨廠區或跨時區的時間戳資料很有用 |
| **診斷** | `dump-collect` | dotnet/skills | 設定與收集 crash dump |
| | `dotnet-trace-collect` | dotnet/skills | 選擇與收集效能診斷資料 |
| | `microbenchmarking` | dotnet/skills | BenchmarkDotNet 效能量測 |
| | `binlog-failure-analysis` | dotnet/skills | 用 MSBuild binlog 分析建置失敗；主要流程需要它附的 binlog MCP server，只複製 SKILL.md 效果會打折 |
| **套件管理** | `convert-to-cpm` | dotnet/skills | 改用 Directory.Packages.props 統一管理 NuGet 版本 |
| | `nuget-manager` | awesome-copilot | 規定用 `dotnet` CLI 管理套件 |
| **Web API** | `dotnet-webapi` | dotnet/skills | ASP.NET Core Web API 端點、OpenAPI、錯誤處理 |
| **測試框架** | `csharp-xunit` / `csharp-nunit` / `csharp-mstest` | awesome-copilot | 各測試框架的寫法慣例；依專案使用的框架挑一個 |
| | `writing-mstest-tests` | dotnet/skills | MSTest 專用，由 .NET 官方維護，著重修正與現代化既有測試 |
| **文件** | `acquire-codebase-knowledge` | awesome-copilot | 接手陌生或老舊專案時，產生程式架構文件 |
| | `create-architectural-decision-record` | awesome-copilot | 撰寫 ADR（架構決策紀錄） |
| | `documentation-writer` | awesome-copilot | 依 Diátaxis 架構撰寫技術文件 |
| **Windows 腳本** | `batch-files` | awesome-copilot | .bat / .cmd 腳本撰寫與除錯 |
| **開發流程** | `test-driven-development` | superpowers | 先寫測試再實作 |
| | `receiving-code-review` | superpowers | 收到 review 意見時先查證、再決定是否採納 |

---

## 5. 給 Skills 維護者的工具

| 工具 | 來源 | 用途 | 注意 |
|---|---|---|---|
| `skill-creator` | anthropics/skills（Apache 2.0） | 寫 skill 的方法論、description 怎麼寫才會被觸發 | 附帶的評測腳本是為 Claude 設計的，主要參考它的寫作指引 |
| `microsoft-skill-creator` | awesome-copilot | 為 Microsoft 技術寫 skill | 需要 Microsoft Learn MCP |
| `suggest-awesome-github-copilot-skills` | awesome-copilot | 依目前 repo 內容推薦 awesome-copilot 裡的 skill | 適合定期找新 skill |
| `agent-skill-stack` | awesome-copilot | 依一個目標挑出最小一組互相搭配的 skill | — |
| `gh skill`（GitHub CLI 2.90 以上，公開預覽） | GitHub | `preview` 看內容、`install` 安裝並鎖定版本、`update` 依內容 hash 偵測上游更新 | 只支援 GitHub 上的 repo；適合維護者在家或可上 GitHub 的環境抓上游、審查後再搬進公司 GitLab |

---

## 6. 不建議或要特別注意

| 項目 | 原因 |
|---|---|
| anthropics/skills 的 `docx`、`pdf`、`pptx`、`xlsx` | 授權明文禁止在 Anthropic 服務以外保留副本、複製、修改或散佈，**不能放進共用 repo** |
| superpowers 整包，特別是 `using-superpowers` | 它要求每次回覆前都先呼叫 skill，會強迫改變 Copilot 的整體行為；`writing-plans`、`requesting-code-review`、`writing-skills` 等則依賴子代理（subagent）、git worktree，以及和 superpowers 其他 skill 串接。只挑第 3、4 章列出的個別 skill |
| awesome-copilot 中含 `${input:...}` 的 skill（約 13 個，例如 `refactor-method-complexity-reduce`） | 它們是由 VS Code prompt file 轉來的，依賴手動輸入參數，不適合讓 Copilot 自動觸發 |
| 內容很短的 skill（例如 `create-readme` 只有約 20 行、`review-and-refactor` 約 15 行） | 價值有限，不如把需求寫進我們自己的規範 skill |
| dotnet/skills 的 `csharp-expert` | 它的工作是「推薦安裝哪個 plugin」，複製到共用 repo 後沒有作用 |
| trailofbits/skills | CC BY-SA 4.0：修改後再散佈必須沿用同授權並標示出處。內容以資安研究、fuzzing、智慧合約為主；有專門資安審查需求時再個別評估（例如 `differential-review`、`semgrep`、`codeql`） |
| microsoft/skills | 以 Azure 與 AI Foundry 為主，沒有使用 Azure 的專案不需要 |
| 任何附帶腳本的 skill | Agent 可能會執行這些腳本，導入前必須逐行看過；`.sh` 腳本在 Windows 上也不一定能跑 |

---

## 7. 怎麼導入到共用 repo

我們的同步程式只管理 `cim-` 開頭的 skill，而且規格要求 `name` 必須和資料夾同名。所以外部 skill 要**改名後放進共用 repo**，不要讓每個人自己另外安裝，否則同一個 skill 會被載入兩份。

### 7.1 步驟

1. **審查內容**：在可以上 GitHub 的電腦用 `gh skill preview` 預覽，或直接看原始碼。每個附屬腳本都要看過。
2. **複製並改名**：把資料夾複製到 `skills/cim-<名稱>/`，`name` 改成相同的名稱。
3. **補中文關鍵字**：在 `description` 最後加上中文關鍵字，因為課內常用中文提問。MIT 和 Apache 2.0 都允許修改。
4. **保留授權與來源**：
   - 上游的 `LICENSE` 檔放在 skill 資料夾內。
   - 在 frontmatter 記錄來源與版本。
5. **走正常流程**：本機跑 `python tools/lint_skills.py` → 發 MR → beta 頻道試用 → 發版。
6. **定期對照上游**：每季比對上游 commit，有重要更新再發 MR 同步。

### 7.2 frontmatter 範例

```yaml
---
name: cim-sql-impact-analysis
description: "Before modifying a table, column, stored procedure, view, or trigger in a legacy codebase, trace every place that references it ... 中文關鍵字 - 影響分析、改表前檢查、預存程序相依、欄位異動."
license: MIT (see LICENSE)
metadata:
  owner: "CIM Skills Maintainers"
  source: "github/awesome-copilot/skills/sql-object-impact-analysis"
  source-ref: "70ddff7"
---
```

（`...` 代表上游原本的英文描述。我實際用 lint 測過，改名後的上游 skill 可以通過檢查。）

### 7.3 建議的導入節奏

| 時間 | 動作 |
|---|---|
| POC 第 2 週 | 從第 3 章挑 3～5 個（建議 #2、#4、#7、#9、#10），和課內自製的 skill 一起發 v1.0.0 |
| 試行期間 | 收集哪些 skill 常被觸發、哪些結果不好 |
| 正式導入後 | 每季依回饋從第 4 章補充，並移除沒人用的 skill |

---

## 8. 參考連結

- dotnet/skills：https://github.com/dotnet/skills
- dotnet/skills 評測儀表板：https://dotnet.github.io/skills/
- github/awesome-copilot：https://github.com/github/awesome-copilot
- obra/superpowers：https://github.com/obra/superpowers
- anthropics/skills：https://github.com/anthropics/skills
- trailofbits/skills：https://github.com/trailofbits/skills
- microsoft/skills：https://github.com/microsoft/skills
- github/copilot-plugins：https://github.com/github/copilot-plugins
- GitHub CLI `gh skill`（2026-04 changelog）：https://github.blog/changelog/2026-04-16-manage-agent-skills-with-github-cli/
- Agent Skills 規格：https://agentskills.io/specification
