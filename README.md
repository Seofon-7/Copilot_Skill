# Copilot Skills 課級共用與集中管理機制

研究文件、報告簡報與 POC 程式。

| 內容 | 位置 | 說明 |
|---|---|---|
| 📄 說明文件 | [docs/copilot-skills-sharing-guide.md](docs/copilot-skills-sharing-guide.md) | 完整的研究規劃、方案比較、架構設計、POC 程式碼與操作手冊 |
| ⭐ 推薦 Skills | [docs/recommended-skills.md](docs/recommended-skills.md) | 目前值得導入的公開 Agent Skills（.NET、SQL、除錯、測試），含授權與導入方式 |
| 📊 報告簡報 | [slides/copilot-skills-sharing-presentation.pptx](slides/copilot-skills-sharing-presentation.pptx) | 17 頁，每頁附講稿備註（點進去後按右上角下載） |
| 🧪 POC 程式 | [poc/cim-copilot-skills/](poc/cim-copilot-skills/) | 共用 skill repo 的完整內容（v1.1.0，13 個 skill），可直接搬到公司 GitLab |

## 快速導覽

- 結論摘要：說明文件第 1 章
- 方案比較：說明文件第 4 章
- 建議架構：說明文件第 5 章
- POC 操作步驟：說明文件第 10 章
- 第一批要導入哪些公開 skill：推薦清單第 3 章
- 第一週要問 IT／主管的問題：說明文件附錄 A

## 注意

- 文件與程式中的 `gitlab.example.local`、`\\fileserver\CIM\...`、`@cim/skills-maintainers` 都是範例值，使用前請換成公司實際的位址與群組。
- POC 程式已在模擬環境測試通過，尚未在公司 Windows 電腦上實測（見說明文件第 10.4 節）。
