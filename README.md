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

## Requirements

- macOS 14.0 (Sonoma) or later
- Xcode 15+ (to build)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (to generate the Xcode project)
- Git installed and configured

## Installation

### Build from source

1. **Clone the repo:**
   ```bash
   git clone https://github.com/farzanariel/GitPush.git
   cd GitPush
   ```

2. **Install XcodeGen** (if you don't have it):
   ```bash
   brew install xcodegen
   ```

3. **Generate the Xcode project:**
   ```bash
   xcodegen generate
   ```

4. **Build and run:**

   **Option A — Xcode:**
   Open `GitPush.xcodeproj`, select the GitPush scheme, and hit Run (Cmd+R).

   **Option B — Command line:**
   ```bash
   xcodebuild -project GitPush.xcodeproj -scheme GitPush -configuration Release build
   ```
   Then copy the built `.app` from `DerivedData` to `/Applications`:
   ```bash
   cp -r ~/Library/Developer/Xcode/DerivedData/GitPush-*/Build/Products/Release/GitPush.app /Applications/
   ```

5. **Launch GitPush** — it appears in your menu bar (no Dock icon).

### Launch at login (optional)

Go to **System Settings → General → Login Items** and add GitPush.

## Setup

Click the menu bar icon, then the gear icon to open Settings:

1. **Projects Directory** — path to your projects folder (default: `~/Documents/Projects`). GitPush scans for active repos here.

2. **AI Provider** — choose between **Claude** (Anthropic) or **OpenAI** for commit message generation:
   - Claude: uses Haiku — paste your `sk-ant-...` key
   - OpenAI: uses GPT-4o mini — paste your `sk-...` key

3. **Auto-generate commit messages** — when enabled, expanding a repo automatically generates a commit message from the diff.

4. **Global hotkey** — toggle `Cmd+Shift+G` to commit & push all repos with changes.

## Usage

- **Click the menu bar icon** to see your active repos with changes
- **Click a repo** to expand it — see changed files, edit or generate a commit message
- **Click the blue arrow** or **"Commit & Push"** to commit all changes and push
- **"Push All"** commits and pushes all repos at once
- **`Cmd+Shift+G`** (global) — commit & push all active repos instantly

## How it works

GitPush uses `lsof -d cwd` to check which processes have their working directory inside your projects folder. It matches against known editor and shell process names (Cursor, VS Code, Xcode, zsh, bash, vim, Claude, etc.) to determine which repos you're actively working on.

Only repos with uncommitted changes are shown. After a successful commit & push, the repo disappears from the list.

## Project structure

```
GitPush/
├── project.yml                    # XcodeGen project config
├── GitPush/
│   ├── GitPushApp.swift           # App entry point, MenuBarExtra
│   ├── Info.plist                 # LSUIElement (no Dock icon)
│   ├── Models/
│   │   ├── Repository.swift       # Repo data model
│   │   └── AppState.swift         # Observable app state
│   ├── Views/
│   │   ├── MenuBarView.swift      # Main popover + settings
│   │   └── RepoRowView.swift      # Repo row + animations
│   └── Services/
│       ├── GitService.swift       # Git CLI operations
│       ├── AIService.swift        # Claude & OpenAI API
│       ├── RepoWatcher.swift      # Repo scanning timer
│       └── HotkeyService.swift    # Global keyboard shortcut
```

## License

MIT
