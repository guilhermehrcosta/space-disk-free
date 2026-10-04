# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Space Disk Free is a macOS 14+ menu bar app (SwiftUI `MenuBarExtra`, `LSUIElement`) that shows what is using disk space and cleans it up. The UI is localized in English (source language) and Brazilian Portuguese.

## Conventions

- Don't write code comments (`//`, `///`, or `#` explanations in scripts, Makefile and YAML). Explain the reasoning in the PR description. `// swift-tools-version` in `Package.swift` and the shebangs are syntax, not comments.
- Every change goes on a branch and is delivered as a pull request. Never commit directly to `main`.
- Commit messages, PR titles and PR descriptions are written in English.
- Commits and PRs carry no Claude attribution (no `Co-Authored-By`, no "Generated with Claude Code").

## Commands

```sh
make app       # release build + bundle -> "build/Space Disk Free.app" (ad-hoc signed, host arch)
make run       # app + kill running instance + open
make install   # copy to /Applications and open
make dmg       # universal (arm64 + x86_64) app -> build/SpaceDiskFree-<version>.dmg, same as the release workflow
make test      # swift test (Swift Testing)
make icon      # regenerate Resources/AppIcon.icns from Scripts/make-icon.swift (drawn with AppKit + SF Symbols; commit the .icns)
make lint      # swift format lint --strict (config: .swift-format); CI fails on any finding
make format    # swift format in place — run before committing
make strings   # rebuild with -emit-localized-strings and sync Resources/Localizable.xcstrings
make clean

swift test --filter SafetyPolicyTests   # one suite or test
```

Requires Xcode selected (`xcode-select -p` → Xcode.app). With only the Command Line Tools, the `Makefile` and `Scripts/build-app.sh` fall back to `--build-system native` and pass the Swift Testing framework paths, but SwiftUI's `@State` won't compile: its macro plugin only ships with Xcode.

## CI / release

- `.github/workflows/ci.yml`: lint runs on Ubuntu in the `swift:6.4` container (cheap minutes; keep it on the same Swift version as local so `swift format` agrees). Tests and an app build run on `macos-15`. The repo is private, and macOS minutes count 10×, so keep the trigger filters (`paths-ignore`, `concurrency`).
- `.github/workflows/release.yml`: publishing a GitHub release tagged `vX.Y.Z` runs tests, builds the universal app with `VERSION` taken from the tag and `BUILD_NUMBER` = run number, then attaches the `.dmg` to the release. There is no Developer ID or notarization (ad-hoc signature), so users have to approve the app once in Privacy & Security.
- `build-app.sh` builds each arch separately and merges them with `lipo`. Each slice is copied right after its build because the Xcode build backend uses the same output dir for every arch.

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

  A category can have several `CleanupAction`s (the first one is primary, and the UI shows a menu). Docker is an example: quick prune, full prune and volume prune. `Cleaner.run(_:action:)` rejects any action that doesn't belong to the category. Commands run against whatever engine the current `docker context` points to (Docker Desktop, Rancher Desktop or Colima), so the Docker category measures those VM disks. If `Docker.app` is gone, its leftover `Docker.raw` becomes a separate trash-only category. `defaults(home:isAppInstalled:)` takes the app check as a parameter so tests can inject it.

  `deleteItems([URL])` deletes specific items computed when the catalog is built. Example: Android system images that no AVD's `config.ini` references (`AndroidSDK`). `Cleaner` rejects the whole batch if any item isn't inside the category's paths, and it prunes the empty parent folders afterwards. `defaults()` runs on every scan, so keep it to cheap I/O (listing dirs, reading small files) and never measure sizes there.

  Only categories whose paths exist are shown. `countsTowardReclaimable` keeps command and review categories out of the "recuperável" total, because their sizes overlap other categories or can't be fully freed.
- **Safety.** `Cleaner.run` checks every category path against `SafetyPolicy.canClearContents`, which resolves symlinks and requires the path to be strictly inside home and not on a protected list. Explorer deletions go through `SafetyPolicy.canTrash` and always go to the Trash, never a permanent delete. Any new category or delete path must pass this policy. The `defaultCategoriesAreAllAllowedByPolicy` test enforces this for the catalog.
- **Explorer cache.** `DirectorySizeCache` (keys = `URL.normalizedPath`, 15 min TTL) lives in `ExplorerModel`. Directories are measured with `SizeCalculator.measureTree`, which records every immediate subfolder in the same `fts` pass, so going back or one level deeper needs no new scan. Category scans feed the same cache. Anything that deletes must keep it consistent: `remove` (explorer trash) or `contentsChanged`/`update` (after a cleanup), which drop the subtree and fix ancestor totals by the delta, or forget the ancestors when the delta is unknown. Never record a measurement from a cancelled task, because it is partial.
- **App state.** `AppState` (`@MainActor @Observable`) owns per-category status, the confirmation dialog, toasts and launch-at-login (`SMAppService`). Every destructive action goes through `pendingConfirmation`, an in-window overlay, instead of `NSAlert`: an alert steals focus and closes the `MenuBarExtra` window. `ExplorerModel` lists a directory with `DirectoryLister`, then measures subdirectories with at most 4 in flight, re-sorting by size as results arrive. Packages (`.app` etc.) count as leaves.
- **Empty Trash fallback.** Without Full Disk Access, `~/.Trash` can't be read. `Cleaner` then empties it through Finder AppleScript (`osascript`), which is why `Resources/Info.plist` has `NSAppleEventsUsageDescription`.

### Localization

- User-facing strings are written in English in code: SwiftUI literals (`Text`, `Button`, `.help`…) and `String(localized:)` for every `String` shown to the user, DiskCore category titles and errors included. Anything passed to `Text` as a `String` variable shows verbatim, so localize it where it's built.
- `Resources/Localizable.xcstrings` holds the pt-BR translations. After adding or changing a string, run `make strings`, then fill in the pt-BR value. Its keys come from the compiler (`-emit-localized-strings`), so interpolations get real format specifiers (`%@`, `%lld`, `%d`). `xcstringstool extract` doesn't work here, because it emits `%arg` keys that never match at runtime.
- `LocalizationTests` fails when a key has no translated pt-BR value or its placeholders differ. CI runs `make strings-check`, which fails when the catalog is out of sync with the code.
- `build-app.sh` compiles `Resources/*.xcstrings` into `.lproj` folders inside the app. `InfoPlist.xcstrings` translates the `Info.plist` privacy strings.

### Packaging

`Resources/Info.plist` is copied in by `Scripts/build-app.sh`; SwiftPM doesn't process it. The app isn't sandboxed because it has to read the whole home folder. The ad-hoc signature changes on every build, so TCC permissions (Full Disk Access) may need to be granted again after rebuilding.
