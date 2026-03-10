# GitPush

A native macOS menu bar app for one-click git commit & push. No terminal needed.

GitPush lives in your menu bar and automatically detects repos you're actively working on — if you have a project open in your editor or a terminal `cd`'d into it, it shows up. Commit and push with a single click, or use a global keyboard shortcut.

## Features

- **Menu bar native** — lightweight, always accessible, no Dock icon
- **Auto-detects active repos** — watches for projects open in editors (Cursor, VS Code, Xcode, Zed, etc.) and terminals (zsh, bash, Claude Code, vim, etc.)
- **One-click commit & push** — or expand to see changed files and edit the commit message
- **AI commit messages** — generates commit messages from your diff using Claude or OpenAI
- **Global keyboard shortcut** — `Cmd+Shift+G` to commit & push all active repos instantly
- **Live status** — menu bar shows "Committing..." and "Pushing..." with animations during operations
- **Progress indicators** — spinning animation while committing, bouncing arrow while pushing, checkmark on success

## Install

1. **[Download GitPush.app.zip](https://github.com/farzanariel/GitPush/releases/latest/download/GitPush.app.zip)**
2. Unzip and drag **GitPush.app** to `/Applications`
3. Launch it — the icon appears in your menu bar

> **First launch:** macOS may say the app is from an unidentified developer. Go to **System Settings → Privacy & Security** and click **Open Anyway**. You only need to do this once.

### Launch at login (optional)

Go to **System Settings → General → Login Items** and add GitPush.

## Setup

Click the menu bar icon, then the gear icon:

1. **Projects Directory** — path to your projects folder (default: `~/Documents/Projects`)
2. **AI Provider** — choose **Claude** or **OpenAI** for AI commit messages:
   - Claude: uses Haiku — paste your `sk-ant-...` key
   - OpenAI: uses GPT-4o mini — paste your `sk-...` key
3. **Auto-generate** — automatically generate a commit message when you expand a repo
4. **Global hotkey** — toggle `Cmd+Shift+G` to commit & push all repos

## Usage

- **Click the menu bar icon** to see active repos with changes
- **Click a repo** to expand — see changed files, edit or generate a commit message
- **Click the blue arrow** or **"Commit & Push"** to commit and push
- **"Push All"** commits and pushes all repos at once
- **`Cmd+Shift+G`** — commit & push everything instantly

## How it works

GitPush checks which processes have their working directory inside your projects folder (`lsof -d cwd`). It matches against known editors and shells to find repos you're actively working on. Only repos with uncommitted changes are shown — after a successful push, the repo disappears.

## Build from source

Requires macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
git clone https://github.com/farzanariel/GitPush.git
cd GitPush
brew install xcodegen
xcodegen generate
xcodebuild -project GitPush.xcodeproj -scheme GitPush -configuration Release build
```

## License

MIT
