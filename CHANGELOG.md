# Changelog

All notable changes to Dylan. Dylan shows the section for your version once after an update (Settings → About → What's New).

## [0.1.4] - 2026-11-04

### Added
- About shows the author, Egie Ramdan, with links to GitHub and the source code (Settings → About, and "About Dylan" in the menu bar).

## [0.1.3] - 2026-11-04

### Added
- Screenshot editor: after Save, the notch shows "Click to open in Finder" with the file path and a Finder button.

## [0.1.2] - 2026-11-04

### Added
- Update check: Dylan can look for new releases on GitHub (Settings → About), shows the release notes, and downloads the DMG. Automatic daily checks are opt-in; "Check now" is always there.
- What's New: after an update, Dylan shows what changed in your version once.
- Face Unlock results in the notch: "Face · 09:12", then a Peek with the match score, how long the Mac was locked, and a History button. A red "Turned off" notice explains when Face Unlock stops.

### Changed
- Screenshots: after you pick an area, a spinner shows right away and the editor opens without a frozen pause.
- Screenshot editor: Copy (⌘C) and Save (⌘S) are icons right after the window buttons.
- Face Unlock settings say whether it is ready, or why not (for example a missing Accessibility permission).

### Fixed
- Face Unlock no longer waits for a password unlock every time Dylan restarts (a Mac restart still requires one).
- "Lock now to try" also turns the display off, so the camera actually starts when you wake it.

## [0.1.1] - 2026-11-04

### Added
- Face Unlock enrollment in four steps with a live camera preview and a 20-frame progress ring.
- Face Unlock has its own Settings section.

### Changed
- Smoother capture crosshair and loupe.
- Arrows, boxes, and highlights draw live while you drag.

### Fixed
- Esc always cancels the capture crosshair, even when the shortcut was pressed in another app.

## [0.1.0] - 2026-11-04

First test build.

### Added
- The notch as a live status center: Compact, Peek, and Expanded, with Home, Media, Shelf, Clipboard, Stats, and Temperature tabs.
- Music (Spotify, Apple Music, browser tabs, VLC), lyrics, per-app volume, live equalizer.
- Screenshots: area, window, screen, scrolling, and text (OCR), an annotation editor and a Studio.
- Temperatures and fan control with a privileged helper that always hands the fans back to macOS.
- Notifications, calls, meeting controls, Discord, devices, and everyday helpers.
- Developer Mode: AI agents (Claude Code, Codex, Cursor, OpenCode), command tracker, Live Activity CLI, ports, GitHub, and more.
