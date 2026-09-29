# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build Commands

```bash
# Build app bundle (also generates the icon and ad-hoc signs it)
./build.sh

# Install to /Applications (remove first: cp -r into an existing .app merges)
rm -rf /Applications/ClaudeNotify.app
cp -r .build/release/ClaudeNotify.app /Applications/

# Load LaunchAgent (auto-start)
launchctl load ~/Library/LaunchAgents/com.claude.notify.plist
```

## Architecture

A macOS menu bar notification daemon for Claude Code, written in Swift using Cocoa/AppKit.

**Single-file design**: All code lives in `Sources/main.swift`.

**App bundle**: Built as `.app` bundle (required for `UNUserNotificationCenter`).

**Two modes of operation**:
1. **Daemon mode** (`--daemon`): Runs as menu bar app, listens for notifications via `DistributedNotificationCenter`
2. **Client mode** (`-m <message>`): Sends notification to running daemon, or starts daemon + sends if not running

**Key components in `main.swift`**:
- `SingleInstance`: Lock file mechanism (`/tmp/claude-notify.lock`) to prevent multiple daemons
- `AppDelegate`: NSApplicationDelegate managing menu bar UI, notification center, and IPC
- `NotificationArgs`: Struct for notification parameters
- CLI argument parsing at file bottom (no external dependencies)

**IPC**: Uses `DistributedNotificationCenter` with notification name `com.claude.notify.send`.

**Sound**: Uses `afplay` to play system sounds (more reliable than `UNNotificationSound`).

## Files

- `Sources/main.swift` - All app code
- `build.sh` - Builds binary and creates .app bundle with Info.plist
- `com.claude.notify.plist` - LaunchAgent for auto-start at login
- `Formula/claude-notify.rb` - Homebrew formula (for future tap)

## Requirements

- macOS 13+ (Ventura)
- Swift 5.9+
