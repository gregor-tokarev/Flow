# Flow for iOS

A native UIKit app for iPhone and iPad, with local notes, tasks, folders, and attachments. Requires iOS 16 or later and Xcode 16 or later. The Android app stays in `app/`.

## Run

Open `ios/Flow.xcodeproj`, select the **Flow** scheme and an iPhone or iPad simulator, then run. Xcode resolves the local `FlowCore` package and its pinned ZIPFoundation dependency automatically.

To install on a physical device, choose your development team in the Flow target's Signing & Capabilities settings and use a bundle identifier registered to that team.

From the repository root:

```sh
xcodebuild -project ios/Flow.xcodeproj -scheme Flow \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath ios/.build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

## Use

- Tap **+** to create an entry. The editor saves after a brief pause in typing and flushes pending changes when you leave or background the app. Use the Note/Task control to change its type, and the circle button to complete a task.
- Swipe an entry for quick actions, or hold it for a context menu. Tap **Edit** and drag the handles to reorder entries.
- Enable **Folders** in Settings to organize entries. The folder picker supports creation, renaming, deletion, and reordering. With folders disabled, the home screen shows all entries.
- Attach files through the paperclip button and tap a file to preview it with Quick Look. The share button shares the entry text and its attachments.
- **Undo** restores deleted entries, folders, and attachments during the current session, up to 20 deletions. Unreferenced attachment files are removed at the next launch.
- Settings includes system, monospaced, and serif fonts, preview length, default entry type, a code keyboard, and a pure black dark background.

## Backups and storage

Settings can export and import `.flow` ZIP backups using the same version 1 manifest, JSON metadata, and attachment layout as Android. Version 5 legacy JSON backups can also be imported. Import shows the contents and asks before replacing the library. It validates the archive and stages attachment files before updating the saved library.

Import limits are 32 MB per metadata file, 512 MB per attachment, and 2 GB of attachments per backup. Preferences are device-specific and are not included in backups.

Restore copies files and writes the library away from the main thread. Other library changes are blocked until it finishes. If an attachment file is missing at startup, Flow warns you and preserves its record while keeping your notes accessible. If the library itself cannot be opened, **Start a new library** moves the original directory to a timestamped sibling in Application Support before creating a fresh library, so the original files remain available for recovery.

The app stores `library.json` and attachment files under its Application Support directory. Saves replace the JSON file atomically. The app excludes this directory from device backups and uses no network services, analytics, account, or cloud sync. Export a `.flow` backup before uninstalling the app or moving to another device.

The interface currently uses English. It follows the system appearance and supports Dynamic Type and VoiceOver labels. Android-only features such as Material dynamic colors and Android keyboard behavior use native iOS equivalents where available.

## Tests

Run the persistence and backup tests on macOS:

```sh
swift test --package-path ios/FlowCore
```

Run the UIKit flows on an available simulator, replacing the destination name if necessary:

```sh
xcodebuild -project ios/Flow.xcodeproj -scheme Flow \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -derivedDataPath ios/.build/DerivedData CODE_SIGNING_ALLOWED=NO test
```

UI tests use a separate library directory through Debug-only launch arguments. They cover editing, completion, deletion/undo, relaunch persistence, folders, settings, and search. The backup fixtures follow the Kotlin serializers in `app/src/main/java/dev/jvqtil/flow/data/backup/` and include Unicode text and attachment bytes.

## Source layout

- `Flow/`: UIKit lifecycle, controllers, assets, and preferences.
- `FlowCore/`: Foundation data model, atomic local store, backup reader/writer, and unit tests.
- `FlowUITests/`: simulator tests.

ZIPFoundation is pinned to 0.9.20 under the MIT license. Its package includes its own privacy manifest. The app's privacy manifest declares its use of local preferences and file timestamps.
