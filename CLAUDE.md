# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Space Disk Free is a macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement`) that shows what is using disk space and cleans it up. The UI text and user-facing docs are in Brazilian Portuguese, so keep new strings in pt-BR.

## Commands

```sh
make app       # release build + bundle -> "build/Space Disk Free.app" (ad-hoc signed)
make run       # app + kill running instance + open
make install   # copy to /Applications and open
make test      # swift test (Swift Testing)
make clean

# Run one suite or test (same flags `make test` passes):
F=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
swift test --build-system native -Xswiftc -F -Xswiftc $F -Xlinker -F -Xlinker $F -Xlinker -rpath -Xlinker $F --filter SafetyPolicyTests
```

There is no linter configured.

### Toolchain constraints (Command Line Tools only, no Xcode yet)

- Plain `swift build` fails with "Unknown error parsing property list". The default Swift Build backend doesn't initialize without Xcode, so always pass `--build-system native`. `Scripts/build-app.sh` and the `Makefile` already do this.
- **Don't use `@State` in SwiftUI.** On the macOS 27 SDK it's a macro whose plugin (`SwiftUIMacros`) only ships with Xcode. View-local state lives on the `@Observable` models instead, for example `AppState.selectedTab` and `ExplorerModel.hoveredNode`. `@Observable`, `@Environment` and `@AppStorage` work fine.
- The Swift Testing framework isn't on the default search path, so tests need the `-F`/`-rpath` flags above.
- Xcode is being installed. Once `xcode-select -p` points to Xcode.app, these workarounds can be removed and `@State` brought back.

## Architecture

There are two SwiftPM targets, and the split is deliberate:

- **`DiskCore`** is a library with no UI. All filesystem logic lives here, and it's the only target with tests (`Tests/DiskCoreTests`).
- **`SpaceDiskFree`** is the SwiftUI app. It holds UI state only and calls into `DiskCore` for anything that touches disk.

### Key flows

- **Measuring sizes.** `SizeCalculator.measure` walks the tree with `fts(3)` (`FTS_PHYSICAL | FTS_XDEV`), adds up `st_blocks * 512`, de-duplicates hard links by inode, and checks `Task.isCancelled` every 4096 entries. It's synchronous and blocking by design. Callers run it inside task-group child tasks or `Task.detached` so it stays off the main actor. `SizeResult.permissionDenied` drives the Full Disk Access banner in the UI.
- **Cleanup categories.** `CleanupCategory.defaults(home:)` is the single catalog. Each category has a `CleanupStrategy`:
  - `deleteContents` / `trashContents` / `emptyTrash` empty the category's folders.
  - `command` runs a tool via `zsh -lc` (a login shell, so the Homebrew PATH works).
  - `review` cleans nothing; it opens the folder in the Explorar tab.

  Only categories whose paths exist are shown. `countsTowardReclaimable` keeps command and review categories out of the "recuperável" total, because their sizes overlap other categories or can't be fully freed.
- **Safety.** `Cleaner.run` checks every category path against `SafetyPolicy.canClearContents`, which resolves symlinks and requires the path to be strictly inside home and not on a protected list. Explorer deletions go through `SafetyPolicy.canTrash` and always go to the Trash, never a permanent delete. Any new category or delete path must pass this policy. The `defaultCategoriesAreAllAllowedByPolicy` test enforces this for the catalog.
- **App state.** `AppState` (`@MainActor @Observable`) owns per-category status, the confirmation dialog, toasts and launch-at-login (`SMAppService`). The `App` struct holds it as a plain `let`. Every destructive action goes through `pendingConfirmation`, an in-window overlay, instead of `NSAlert`: an alert steals focus and closes the `MenuBarExtra` window. `ExplorerModel` lists a directory with `DirectoryLister`, then measures subdirectories with at most 4 in flight, re-sorting by size as results arrive. Packages (`.app` etc.) count as leaves.
- **Empty Trash fallback.** Without Full Disk Access, `~/.Trash` can't be read. `Cleaner` then empties it through Finder AppleScript (`osascript`), which is why `Resources/Info.plist` has `NSAppleEventsUsageDescription`.

### Packaging

`Resources/Info.plist` is copied in by `Scripts/build-app.sh`; SwiftPM doesn't process it. The app isn't sandboxed because it has to read the whole home folder. The build is arm64-only with an ad-hoc signature, so TCC permissions may reset on each rebuild. Distributing to other people needs a universal binary plus Developer ID signing and notarization, which isn't set up yet.
