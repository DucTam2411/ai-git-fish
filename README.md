# ai-git-fish

AI-assisted git for [fish](https://fishshell.com). Three functions, powered by DeepSeek + optional [Leantime](https://leantime.io) ticket linking:

| Command | Does |
|---------|------|
| `aicommit [hint]` | Generate a Conventional Commit message from your **staged** diff, preview it, commit on confirm. |
| `aibranch [type]` | fzf-pick a Leantime ticket assigned to you, create/switch to `type/<id>-<slug>` (default `type` = `feat`). |
| `aipr [hint]` | Push the branch, write a PR title + markdown body (with a `🧪 How to test` checklist) from your commits, link the Leantime ticket, create or update the GitHub PR, notify Slack reviewers (if configured). |
| `aitask [headline]` | Create a Leantime task assigned to **you**: fzf-pick project, fzf-pick sprint, create the ticket. |
| `aibpm [headline]` | Create a task in the BPM project (Anymateme Web platform, fixed — no project picker): fzf-pick sprint, fzf-pick the **assignee**, create the ticket. |
| `aibpm board` | BPM sprint board: pick a sprint, browse its tasks grouped by assignee. Pick a task to set its status, or the `➕ New task` row to add one to that sprint — both loop back to the refreshed board until you exit. |
| `aidone [id]` | fzf-pick a Leantime ticket (or pass an id) and mark it Done. |
| `aistatus [id]` | Dashboard loop: fzf-pick a Leantime ticket assigned to you (or pass an id for the first round), fzf-pick any status to set it to, then back to the ticket list — refreshed — until you exit the picker. |

All three auto-detect a ticket id from the branch name (`\d{3,}`), an `AICOMMIT_TICKET` / `AIPR_TICKET` env var, a `#1234` in your hint, or an fzf picker.

## Prerequisites

- `fish` ≥ 3.4 and [fisher](https://github.com/jorgebucaran/fisher)
- `git`, `curl`, `jq`, `gh` (authenticated: `gh auth login`)
- `node` ≥ 18 (provides `npx`; `tsx` is installed locally by the bootstrap)
- `fzf` — for the interactive ticket picker
- *optional* `gitleaks` — `aicommit` runs a staged-secret scan before any diff leaves your machine
- `python3` — powers the commit-preview grid and `aicommit`'s dump-code scan (blocks hardcoded `localhost`/loopback host defaults; override an intentional one with `AICOMMIT_ALLOW_SMELLS=1`)

```sh
brew install jq gh fzf node gitleaks   # macOS
```

## Install

### Guided installer (recommended)

```sh
fish (curl -sL https://raw.githubusercontent.com/DucTam2411/ai-git-fish/main/install.fish | psub)
```

It will:

- check deps and **offer to install** missing ones (macOS `brew`; Linux `apt`/`dnf`/`pacman`)
- run `gh auth login` if you're not authenticated
- `fisher install` the plugin (which downloads the Leantime backend + `npm install`)
- prompt for `DEEPSEEK_API_KEY` (saved as a universal var)
- prompt for `LEANTIME_BASE_URL` / `LEANTIME_API_KEY`, then **fzf-pick your user** to set `LEANTIME_USER_ID`
- prompt for `SLACK_WEBHOOK_URL` (optional) + reviewer mentions

Re-runnable any time to reconfigure.

### Manual

```sh
fisher install DucTam2411/ai-git-fish
```

A `conf.d` hook downloads the Leantime backend into `~/.config/fish/leantime` and runs `npm install` (override with `LEANTIME_SCRIPT_DIR`). Then configure as below.

**Private repo?** Each dev needs read access plus working git auth (SSH key or the `gh` credential helper) for `fisher install` to clone. The bootstrap fetches the backend via authenticated `gh` (run `gh auth login` first), falling back to public `curl` otherwise.

## Configure

1. **DeepSeek key** — required by `aicommit` / `aipr`. Put in `~/.config/fish/config.fish` (or a gitignored file you source):

   ```fish
   set -gx DEEPSEEK_API_KEY sk-xxxxxxxx
   ```

2. **Leantime** — required by `aibranch` and the ticket-linking in `aicommit`/`aipr`. Edit the seeded `.env`:

   ```sh
   $EDITOR ~/.config/fish/leantime/.env
   ```
   ```ini
   LEANTIME_BASE_URL=https://your-leantime.example.com
   LEANTIME_API_KEY=your-leantime-api-key
   LEANTIME_USER_ID=your-numeric-user-id
   ```

`aicommit` and `aipr` work **without** Leantime — they just skip the ticket section. `aibranch` needs it.

3. **Slack** (optional) — `aipr` posts a PR notification (author, link, ticket, @-mentioned reviewers) to a channel when set. `aigit config` prompts for these; or edit the same `.env` directly:

   ```ini
   SLACK_WEBHOOK_URL=https://hooks.slack.com/services/...
   SLACK_USER_MAP={"alice":"U0123ABCD","bob":"U0456EFGH"}
   SLACK_PR_REVIEWERS=alice,bob
   ```

   Create an [Incoming Webhook](https://api.slack.com/messaging/webhooks) bound to the channel you want. `SLACK_USER_MAP` maps short names (used in `SLACK_PR_REVIEWERS`) to Slack member ids so `aipr` can @-mention them — also accepts raw Slack ids, `here`/`channel`, or subteam ids directly. Without `SLACK_WEBHOOK_URL`, `aipr` just skips the notification.

> Never commit keys. `DEEPSEEK_API_KEY` belongs in your shell env; `.env` is gitignored.

## Usage

```sh
git add -p
aicommit "drop the debug logging"        # preview + commit

aibranch fix                             # pick ticket -> fix/1234-slug

aipr "focus on the migration"            # open / update the GitHub PR

aitask "fix flaky login test"            # pick project -> pick sprint -> create task (assigned to you)

aibpm "fix flaky login test"             # pick sprint -> pick assignee -> create BPM task

aibpm board                              # pick sprint -> board by assignee -> set status / add task -> loop

aidone                                   # pick ticket -> mark Done

aistatus                                 # pick ticket -> pick status -> set it -> back to the list
```

The `aibranch`/`aicommit` ticket picker shows each ticket's live status as an emoji (✅ done, 🆕 new, 🚧 in progress, ⏳ waiting/review, ⛔ blocked, 🗄️ archived) alongside the headline; the full status word is in the fzf preview pane.

## Manage

```sh
aigit update      # pull the latest plugin + backend (fisher update + npm i)
aigit config      # re-enter Leantime creds and re-pick your user id
aigit uninstall   # remove the plugin, optionally the backend dir + DEEPSEEK key
aigit version     # show repo / backend / fisher status
aigit help
```

`aigit update` / `aigit uninstall` wrap `fisher update` / `fisher remove` and add the backend cleanup (`.env`, node deps, the universal `DEEPSEEK_API_KEY`).

## How it bootstraps

Fisher only installs `functions/`, `completions/`, `conf.d/`. The Leantime picker is a small TypeScript project (`leantime/`), so `conf.d/ai-git-fish.fish` fetches it on `fisher install` / `fisher update` and runs `npm install`. To re-run manually:

```fish
__ai_git_fish_bootstrap
```

## Uninstall

```sh
fisher remove DucTam2411/ai-git-fish
```

Your `~/.config/fish/leantime` (holding `.env`) is left in place — delete it by hand if you want it gone.
