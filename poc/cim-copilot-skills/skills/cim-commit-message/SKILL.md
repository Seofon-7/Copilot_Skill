---
name: cim-commit-message
description: 依 CIM 課規範撰寫 Git commit message（Conventional Commits 格式加上需求或問題單號）。當使用者要寫 commit message、整理這次的變更說明、或準備提交程式碼時使用。Keywords - commit message, git commit, conventional commits, 提交訊息, 變更說明.
metadata:
  owner: "CIM Skills Maintainers"
---

# Commit Message 規範

> 這是 POC 範例內容，單號格式請改成課內實際使用的系統。

## 格式

```
<type>(<scope>): <摘要>

<內文：為什麼要改、改了什麼、有沒有需要注意的影響>

Refs: <單號>
```

## type

| type | 用途 |
|---|---|
| feat | 新功能 |
| fix | 修正錯誤 |
| refactor | 重構，不改變行為 |
| perf | 效能改善 |
| test | 新增或修改測試 |
| docs | 文件 |
| chore | 建置、設定、相依套件 |

## 步驟

1. 先看 staged 的變更（`git diff --staged`）；如果沒有 staged 變更，請使用者先 stage 或說明要描述哪些變更。
2. 依變更內容判斷 type 與 scope（scope 用模組或專案名稱，例如 `eap`、`report`）。
3. 摘要不超過 72 個字元，用祈使句描述「這個 commit 做了什麼」。
4. 內文說明原因與影響範圍；純文字修正可以省略內文。
5. 單號一定要問使用者或從分支名稱取得，**不可自行編造**。
6. 一個 commit 只做一件事；變更混雜多個目的時，建議使用者拆成多個 commit。

## 範例

```
fix(eap): 設備斷線重連後重送未確認的事件

斷線期間收到的事件原本會被丟棄，造成 MES 少收資料。
改為暫存在佇列，重連成功後依序重送。

Refs: CIM-1234
```
