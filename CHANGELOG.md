# Changelog

All notable changes to Dylan. Dylan shows the section for your version once after an update (Settings → About → What's New).

## [0.3.3] - 2026-11-13

### Fixed
- Dylan no longer freezes. Asking macOS whether Dylan may control Spotify (or Apple Music, a browser, VLC) could wait forever when that app did not answer, and it waited on the main thread: the menu bar icon, the notch and Quit stopped responding. The check now runs in the background.
- Clicks on the island reach Dylan again. The notch panel sat under the menu bar instead of above it.
- Settings and Dylan's other windows open in front of the app you are using (VS Code, for example) instead of behind it. While one is open, Dylan shows in the Dock and ⌘-Tab.

## [0.3.2] - 2026-11-11

### Fixed
- Dylan no longer quits by itself when a Bluetooth device (AirPods, a mouse, a keyboard) connects or disconnects. On macOS 27.2 the system reports these from a background thread, which stopped the app.

## [0.3.1] - 2026-11-07

### Fixed
- Face Unlock reads head turns precisely. Before, left and right jumped in 45° steps and up or down never registered, so enrolling dragged on and "look up" could never pass. Which way is left and up is now learned from your own turns while you enroll or add an identity.
- Typing the password at the lock screen: the scan island closes first, the password goes in one character at a time, and Return comes after a short pause. In testing, challenges that passed still left the Mac locked.
- Unlocking by hand after a failed attempt is no longer logged as unlocked by face.
- The phone or tablet check no longer fires on a real face in front of a door or a monitor.

### Changed
- Enrollment asks for five directions (straight, left, right, up, down) instead of nine. A small turn of about 10° from where your head starts is enough, and the head dot glides.
- The challenge says "close your eyes for a moment" instead of "blink": a quick blink can fall between camera frames.

### Added
- Practice the challenge (Settings → Face Unlock → Test your face): the real challenge while the Mac is unlocked, with the result and what the camera saw. Nothing is typed or counted.
- Copy history. Each attempt also shows how far you turned, how far your eyes closed, and the scores.

## [0.3.0] - 2026-11-07

### Added
- Face Unlock, after Glance:
  - Face identities: add up to five looks (glasses, a mask, dim light, or someone you trust) and switch each off without deleting it.
  - Guided enrollment: an arc for each of nine head directions, a dot that follows your head, and "come back a little" when you turn too far.
  - A scan island on the lock screen with the move to make, then a tick or a cross (experimental; if macOS refuses, the instructions are spoken).
  - Press space at the lock screen to try again (needs Input Monitoring; off until you turn it on).
  - Test your face: 10 seconds of camera with the score of each identity. Nothing unlocks and nothing is stored.
  - Change the stored password without enrolling again.
  - A trackpad tap when it unlocks or fails.

### Changed
- Face Unlock forgives blurred frames for up to 1.5 seconds in total instead of failing at once (a blink still has to be your face), and fails when a phone or tablet screen frames your face.
- Turning Face Unlock on, a longer lock limit, adding or turning on an identity, a new password and space-to-retry ask for Touch ID first. Turning things off never does.
- Your current enrollment becomes the "Main face" identity; nothing to redo.

## [0.2.1] - 2026-11-05

### Added
- Prayer times can follow your current location (Settings → Prayer times → Use current location): no city to type, and the schedule updates when you travel. The location is rounded to about 1 km and stays on your Mac.

### Changed
- The Colour island style starts from black.

## [0.2.0] - 2026-11-05

### Added
- Prayer times (Settings → Prayer times): the Kemenag schedule for your city, computed on your Mac. A countdown in the notch 30 minutes before each prayer, a Peek when it is time, a Prayer tab with the Hijri date, reminders 5–30 minutes before, and the adhan from an audio file you pick, with the music paused and resumed.
- Focus: set the Pomodoro lengths, breaks start by themselves with a Skip button, and a stopwatch with laps.
- Lyrics: karaoke when the lyrics have word timing, romanized lines for Korean, Japanese, Chinese, Thai and Arabic, and a translation into your language (Apple Translation).
- Notifications: a Notifications tab with today's history (or 7 days), grouped per conversation, and an option to keep the island quiet during a Focus (messages are counted in the ear instead).
- Drop actions: drag files to the top edge and drop them on Shelf, Compress, AirDrop, iCloud Drive (and other synced cloud folders) or Share; images also get Remove background and Resize.
- Island styles: black, colour, glass, frosted, or a floating island. On screens without a notch the pill can be dragged along the top edge and can step aside when the cursor only passes by.
- Home modules (Edit modules): today's tasks, flashcards with spaced repetition (CSV or Anki import), and internet radio.
- Mic mute for every app (`⌃⌥M`) and airplane mode (`⌃⌥⇧A`, Wi‑Fi off and back), in Settings → Devices.
- Animations, one by one (Settings → Animations): a glow around the island for notifications, a timer line, stacked notifications, and confetti when the day's tasks are done.

### Changed
- New menu bar icon from the app icon: the island with two ears, solid while something runs, a dot when something needs you, crossed out in Presentation Mode.

## [0.1.7] - 2026-11-04

### Fixed
- The app icon is back to "Island + ears" (design 4c); 0.1.6 had picked up another icon by mistake.

## [0.1.6] - 2026-11-04

### Added
- Screen recording: `⌥⇧5` or Screenshot ▸ Record Screen, then drag an area or click for the whole screen. Saved as MP4 next to your screenshots, with system audio and, if you turn it on, the microphone. The notch shows a red dot and the time; stop from the notch, the menu or `⌥⇧5`.

### Changed
- Settings redesign (design D50): every page opens with a drawn banner of Dylan's island, a serif title, warm neutrals and Cermin's teal; groups are white cards. Optimize Storage, updates and capture history follow the same look.
- New app icon "Circuit".

## [0.1.5] - 2026-11-04

### Added
- Optimize Storage (menu bar, Settings → Storage): scan caches, logs, old downloads, large files, iPhone backups and, in Developer Mode, Xcode data, package caches and old node_modules. Check what to remove; each item shows its size, location and what happens if you remove it. Things that rebuild themselves are deleted, your own files go to the Trash.
- A notch warning when the disk is almost full, with a Clean up button.

### Changed
- Settings sidebar grouped by purpose: Notch, System, Tools, Developer, Info.

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
