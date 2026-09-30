# Native navigation and surfaces

No URL routes or router configuration exist. Navigation is AppModel state within Window("Face Hugger", id: "main"). The complete scene/command source is copied in layouts.md from Sources/FaceHugger/FaceHuggerApp.swift; the full navigation switch and sheet declarations are copied there from MainView.swift.

| State / surface | Component and source | Layout | Rendered content |
|---|---|---|---|
| `sidebar == "uploads"` (default) | `MainView.queue`, `Sources/FaceHugger/MainView.swift` | MainView sidebar, toolbar, optional JobInspector | Every non-completed job; mascot empty state; Start queue; reorderable job list; status footer |
| `sidebar == "history"` | `MainView.queue`, `Sources/FaceHugger/MainView.swift` | Same shell and inspector | Completed jobs only; completion empty state |
| `sidebar == repo.id` where id is `model:owner/name` or `dataset:owner/name` | `RepoBrowser`, `Sources/FaceHugger/RepoBrowser.swift` | Same shell, no upload inspector | Model/dataset files, current path, filter, size table, refresh, file context actions |
| `showUpload` sheet | `UploadSheet`, `Sources/FaceHugger/Sheets.swift` | Native sheet over MainView | Folder, repo/type, destination, include/exclude patterns, replacement explanation, Add to queue / Upload now |
| `showSettings` sheet | `SettingsSheet`, `Sources/FaceHugger/Sheets.swift` | Native sheet over MainView | Runtime setup/repair, connection, token, keep-awake setting |
| `showCreateRepo` sheet | `CreateRepoSheet`, `Sources/FaceHugger/Sheets.swift` | Native sheet over MainView | Owner/name/type and private toggle (default true) |
| Menu bar | `MenuContent`, `Sources/FaceHugger/FaceHuggerApp.swift` | MenuBarExtra | Current upload, stop, show app, quit |

Repository navigation is an onChange of model.sidebar that calls model.browse(repo). Remote folder double-click calls browse(repo,path:); root and Up buttons navigate parents. Upload sheet prepopulates from currentRepo and remotePath. Cmd-N opens folder choice; Shift-Cmd-N opens repo creation; Cmd-comma opens settings. Closing the window preserves the app/menu bar; quitting an active upload asks whether to stop.

## Workflow constraints relevant to design

Queue order persists. Uploads can be stopped/resumed, but completed remote commits remain visible. Multiple pipeline stages overlap; the UI shows an indeterminate row progress bar and real file/commit/data-sent counters in the inspector, not a fabricated overall percentage. Runtime/account errors appear inside active sheets. Remote deletion requires a confirmation dialog and creates a deletion commit. Folder upload is currently configured in one sheet, not a wizard or scan-review screen. There is no overwrite preview, branch UI, pinning UI, or persistent log history.
