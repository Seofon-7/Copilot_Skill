# CIM Copilot Skills

CIM 課共用的 GitHub Copilot Agent Skills。安裝後會自動同步到 `%USERPROFILE%\.copilot\skills\`，Visual Studio 和 VS Code 都會讀取。

## 安裝（每人一次）

```powershell
git clone https://gitlab.example.local/cim/cim-copilot-skills.git $env:TEMP\cim-skills-setup
powershell -ExecutionPolicy Bypass -File $env:TEMP\cim-skills-setup\tools\install.ps1 `
  -RepoUrl https://gitlab.example.local/cim/cim-copilot-skills.git `
  -ReportDir \\fileserver\CIM\copilot-skills-status
```

安裝完成後重新開啟 VS Code / Visual Studio。之後會在登入後與每天自動同步，不需要手動更新。

## 目前收錄的 skill（v1.1.0）

| 分類 | Skill | 用途 | 來源 |
|---|---|---|---|
| 課內規範 | `cim-csharp-coding-standard` | C# 程式撰寫規範 | 課內自製 |
| | `cim-commit-message` | commit message 規範 | 課內自製 |
| | `cim-code-review` | code review 檢查清單 | 課內自製 |
| 測試 | `cim-run-tests` | 下正確的 `dotnet test` 指令與篩選條件 | dotnet/skills |
| | `cim-code-testing` | 為既有程式補單元測試、修失敗的測試 | dotnet/skills |
| | `cim-test-anti-patterns` | 找出沒驗證東西、不穩定等壞測試 | dotnet/skills |
| 重構與效能 | `cim-csharp-refactoring` | 不改變行為的安全重構 | dotnet/skills |
| | `cim-dotnet-performance` | 掃描 .NET 效能反模式 | dotnet/skills |
| SQL | `cim-sql-code-review` | SQL 安全與品質審查 | github/awesome-copilot |
| | `cim-sql-impact-analysis` | 改 table、欄位、預存程序前追出所有影響範圍 | github/awesome-copilot |
| C# | `cim-csharp-async` | async/await 最佳實務 | github/awesome-copilot |
| 工作方法 | `cim-systematic-debugging` | 先找根因再修 | obra/superpowers |
| | `cim-verification-before-completion` | 宣稱完成前先跑驗證 | obra/superpowers |

外部 skill 的授權、來源 commit 與修改內容見 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 常用指令

| 目的 | 指令 |
|---|---|
| 立即同步 | `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cim-skills\bin\cim-skills-sync.ps1"` |
| GitLab 憑證過期，重新登入 | 上面的指令加 `-Interactive` |
| 查看目前版本 | `Get-Content "$env:USERPROFILE\.cim-skills\state.json"` |
| 查看日誌 | `"$env:USERPROFILE\.cim-skills\logs\"` |
| 移除 | `powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.cim-skills\bin\uninstall.ps1"` |

## 規則

- 共用 skill 名稱一律 `cim-` 開頭；請不要在本機直接修改，修改會在下次同步時被還原（原檔會備份在 `%USERPROFILE%\.cim-skills\backup\`）。
- 想客製：複製一份改成不含 `cim-` 的名稱當個人 skill，或發 MR。
- 個人 skill（沒有 `cim-` 前綴）不會被同步程式影響。

## 貢獻新的 skill

1. 開分支，在 `skills/cim-<名稱>/SKILL.md` 撰寫 skill。
2. 本機執行 `python tools/lint_skills.py` 確認沒有錯誤。
3. 在 IDE 實際觸發測試。
4. 發 MR，使用「Skill」範本，等待維護者審核。

維護者合併後會在 main 上試用，確認沒問題再打 tag 發版。
