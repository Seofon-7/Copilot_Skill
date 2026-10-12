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
