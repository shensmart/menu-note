# MenuNote

[中文](README.md)

A Markdown note and task manager for the macOS menu bar. It stays in the menu bar and opens a floating panel with a global shortcut, so you can view and edit notes above any desktop or full-screen app without switching windows.

## Features

- **Menu bar app**: left-click the status bar icon to show or hide the panel; right-click to open the menu
- **Global shortcut**: defaults to `⌥Space`; customize it in Settings
- **Floating panel**: does not take focus; pin it to keep it visible across Spaces, or let it hide automatically when it loses focus
- **Rich Markdown editing**: edit formatted content directly without seeing `#`, `**`, or `- [ ]`; supports headings, bold, italic, strikethrough, inline code, links, blockquotes, code blocks, and lists
- **Task archive**: checking a task records its completion time, removes it from the active list, and moves it to the expandable Completed section
- **Multiple views**: switch between rich editing, Markdown source editing, and read-only preview; use `⌘E` to switch between rich and source editing
- **Multiple notes**: each note is stored as an independent `.md` file
- **Automatic saving**: changes are saved after a short debounce; external file changes are reloaded automatically
- **Launch at login**: optionally start MenuNote automatically when you log in

## Screenshot

![Task hierarchy editing and heading groups](docs/task-hierarchy.png)

## Data location

```
~/Library/Application Support/MenuNote/Notes/*.md
```

Notes are ordinary Markdown files. You can open them with any text editor or store them in iCloud, Dropbox, or another sync folder.

## Build and install

Requires Xcode 15 or the Xcode Command Line Tools:

```bash
./Scripts/build_app.sh
```

The app bundle is generated at `build/MenuNote.app`. Drag it to the Applications folder and double-click it to launch.

For development:

```bash
swift run          # Run directly; launch-at-login is unavailable
swift build        # Build only
swift test         # Run the unit tests
```

## Usage

- `⌥Space` (or your configured shortcut): show or hide the panel
- Configure the shortcut: open Settings, click the shortcut field, and press a key combination containing `⌃`, `⌥`, `⇧`, or `⌘`; press `Esc` to cancel
- Task editing: create a task with the checklist button; use `Tab` / `⇧Tab` to indent or outdent tasks; completing all subtasks completes the parent task; the last task input is kept after deleting the final task
- Completed tasks: expand the Completed section to edit, restore, delete individual tasks, or clear all completed records
- `⌘A`: select all editor content
- `⌘B` / `⌘I`: apply bold / italic to the selection
- `⌘E`: switch between rich editing and Markdown source editing
- `⌘D`: copy the current line or selected block
- `⌘⇧7`: toggle the selected paragraphs as an ordered list
- `⌘K`: use the system link command
- `Esc`: hide the panel
- Pin the window: click the pin button or enable “Pin Window” from the menu bar icon's context menu

## Uninstall

1. Right-click the menu bar icon and choose Quit MenuNote.
2. Delete `MenuNote.app`.
3. To remove all note data, delete `~/Library/Application Support/MenuNote`.
