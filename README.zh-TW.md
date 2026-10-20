<div align="center">

# veland

Agent 說做完了，veland 驗證過才合併。

[![License: MIT](https://img.shields.io/badge/license-MIT-green)](LICENSE) [![Claude Code plugin](https://img.shields.io/badge/Claude_Code-plugin-D97757)](https://code.claude.com/docs/en/plugins)

[English](README.md) · **繁體中文**

</div>

每張 ticket 都先和你一起規劃，在自己的 worktree 裡實作，由 script 驗證而不是聽 agent 說「好了」，再交給一個完全沒看過實作過程的 agent 審查，最後才合併。veland 是 Claude Code 的 plugin；之後也會推出 Codex 版。

## 為什麼需要 veland

放手讓 coding agent 自己做，常見的狀況是：

- **沒驗證就回報完成**：它說測試過了，不代表測試真的有跑；
- **計畫很模糊**：怎樣算做完、會動到哪些檔案、還有誰依賴這些檔案，都沒寫下來；
- **合併前沒人把關**：寫程式的和審程式的是同一個 context。

veland 把每張 ticket 變成一個不靠 agent 自述的流程：

- 一個 session 只處理一張 ticket，下一個 session 需要的東西都在 `.veland/<id>/`；
- 實作一律在獨立的 worktree，不碰 main checkout；
- 計畫要有編號的驗收條件，給你看之前先由 script 檢查過；
- 由 script 驗證：跑專案的 gates，而且新測試在拿掉改動後必須失敗；
- 審查的 agent 只拿到 diff 和計畫，拿不到實作者的說法；
- 每一步都會停下來，讓你可以介入。

## 三個指令

```
/veland:open <idea>     →  draft a GitHub issue ─(you approve)→ gh-<n>
/veland:work <ticket>   →  plan  ─(you approve)→  worktree → implement → commit → red-proof → pre-review gates → verify + cold review → fix → review the fixes
/veland:close <id>      →  rebase → verify → PR / merge → clean up
```

**`/veland:open <idea>`** 把一個想法、bug 或改進變成 GitHub issue，套用 repo 自己的 issue form、label 和 issue type。它會先問清楚這個想法沒交代的產品問題，把草稿給你看，你核准後才建立 issue。

**`/veland:work <ticket>`** 可以接一個 issue，或一段文字描述的任務。它先規劃：問技術問題，寫出計畫，包含驗收條件、會動到的檔案、證明每個條件的測試，然後停下來等你核准。接著在 worktree 裡實作：寫程式、commit、證明新測試在拿掉改動後會失敗、同時跑 gates 和冷審查、修正審查找到的問題，最後回報。

**`/veland:close <id>`** rebase、再驗證一次，然後把整個 branch 壓成一個 squash commit 落地：開 PR 讓你合併、開 PR 並在 checks 通過後自己合併，或在本機合併，最後清理現場。

每一步的細節見 [docs/loop.md](docs/loop.md)（英文）。

## 安裝

```
/plugin marketplace add minanyang/claude-plugins
/plugin install veland@minanyang
```

需要 `git` 和 `node`（18 以上）。`/veland:open`、GitHub issue 形式的 ticket，以及 `pr` / `pr-merge` 兩種 close 模式，還需要已登入的 [`gh`](https://cli.github.com)（`gh auth login`），GitLab 則用 [`glab`](https://gitlab.com/gitlab-org/cli)；沒有的話，`close: local` 一樣能用。veland 在 push 之前會先檢查，缺什麼會告訴你。

### 快速開始

```
/veland:open add a --json flag to the export command
/veland:work 12
/veland:close gh-12
```

1. `/veland:open` 問完問題、給你看草稿，你核准後建立 issue（假設是 #12）。
2. `/veland:work 12` 為 ticket `gh-12` 寫計畫，然後停下來。看完計畫、回答問題或核准後，再執行一次 `/veland:work gh-12`（或直接說「go」）開始實作。
3. `/veland:close gh-12` 把它落地。預設會開 PR；你合併之後，再執行一次 `/veland:close gh-12` 清理。

base branch、gates、close 模式等選用設定放在 `.claude/veland.json`，見 [docs/configuration.md](docs/configuration.md)（英文）。

## 內容

### Agents

呼叫時要寫成 `veland:<name>`（Agent tool 需要這個前綴）。

| Agent | 負責 | 不負責 |
|---|---|---|
| `veland:frontend-engineer` | 在專案現有的前端 stack 裡改 UI | 後端、基礎設施 |
| `veland:backend-engineer` | API、資料存取、伺服器端邏輯 | UI、基礎設施 |
| `veland:devops-engineer` | CI/CD、container、IaC、部署設定 | 應用程式碼 |
| `veland:qa-engineer` | 測試設計、重現 bug、排查不穩定的測試 | 修正式環境的 bug |
| `veland:code-reviewer` | 冷審查；只回報有 80% 以上把握的問題，唯讀 | 修正 |
| `veland:security-reviewer` | 資安審查、威脅建模、相依套件稽核，唯讀 | 修正 |

### Skills

| Skill | 用途 |
|---|---|
| `/veland:open` | 起草 GitHub issue，核准後建立 |
| `/veland:work` | 規劃 ticket，再到 worktree 裡實作、驗證、審查 |
| `/veland:close` | rebase、驗證、落地、清理 |
| `/veland:commit` | 只 commit 這個 session 改過的路徑，訊息照 repo 自己的風格。會直接 commit，只有疑似 secret、範圍不清楚或有不相關的改動時才停下來問。說「message only」就只給草稿 |
| `/veland:code-review` | 審查還沒 commit 的改動 |
| `/veland:code-review-branch` | 審查整個 branch 相對於 base 的改動 |

skills 用到的 script 見 [docs/scripts.md](docs/scripts.md)（英文）。

### Hooks

| Hook | 用途 |
|---|---|
| Guard | 擋下破壞性的 Bash 指令（`rm -rf`、force push、`git reset --hard`…） |
| Context gate | session 已經太大時，拒絕執行 `/veland:work` 和 `/veland:close` |
| Stop gate | 還有驗收條件沒交代清楚時，不讓 session 結束 |
| Grant | 你輸入的流程 skill，其授權在整個 session 內都有效 |

細節見 [docs/hooks.md](docs/hooks.md)（英文）。

## 安全與權限

- **Guard 只是盡力而為，不是 sandbox。** 它比對的是指令文字，所以 script、alias 或 `eval` 都能繞過。
- **公開寫入一律會問。** 建立 issue 和貼規劃留言都不在任何 skill 的 `allowed-tools` 裡，所以就算你已經核准草稿，每次還是會跳出權限詢問。在 auto mode 下則由分類器決定，不會跳出詢問。
- **寫入只吃 ticket id。** push、開 PR、合併 PR 都經過 `veland-land`，它只用 ticket id 組出每個指令，所以不應該在設定裡允許 `gh pr merge` 或 `git push`。
- **授權只在你輸入 skill 的那個 session 有效。** [Grant hook](docs/hooks.md#grant) 只放行符合該 skill 授權的單一指令，subagent 裡不適用，而 veland 的 script 只能用在你輸入 skill 時指定的那張 ticket。
- **有些 script 會執行專案的程式碼。** `veland-verify`、`veland-red-proof` 和 `veland-worktree add` 會跑專案的 gates、setup 和測試，所以授權它們，等同於讓 agent 可以寫入 repo 裡的檔案。

## 授權

veland 以 [MIT License](LICENSE) 授權釋出。

veland 這個名稱指的是本專案；請不要用它命名 fork 或衍生作品，但說明某個 fork 是基於 veland 是可以的。
