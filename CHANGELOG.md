# Changelog

All notable changes to this project are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [1.1.0] - 2026-10-23

### Added

- Menu-bar popover with Read Selection, playback controls, a searchable voice picker with previews and a speed slider.
- Settings page: download Balanced (fp16) and Best (fp32) models, launch at login, Accessibility status and shortcuts.
- `parrot://open` and `parrot://settings`, and a Tinycast **Parrot: Settings** command.

### Changed

- Launch at login now uses macOS's login item service instead of System Events.
- The popover opens at the top of the screen when the menu-bar icon is hidden behind the notch.

## [1.0.0] - 2026-10-23

### Added

- Menu-bar app that reads the selected text aloud with Kokoro, fully offline.
- Hotkeys: ⌥Esc read or stop, ⌥⇧Esc pause or resume, Esc stop while speaking.
- Menu with pause, skip sentence, stop, speed (0.8×–2.5×; 0.5×–2.5× slider since 1.1.0) and 28 English voices.
- `parrot://` URL scheme and Tinycast custom commands.
- One-command `install.sh` with the Kokoro model bundled.
