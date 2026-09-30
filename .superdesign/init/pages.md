# Native page dependency trees

Swift source files share a target and do not import one another; these are recursively traced local symbol/resource dependencies, equivalent to web local-import trees. Framework dependencies (SwiftUI, AppKit, Foundation, Security, UserNotifications, UniformTypeIdentifiers) are omitted. Shared references repeat in each candidate tree for completeness; do not send every listed backend file to a design draft. Select target visual source, compact theme summary, layout, and mascot under the payload budget.

## Uploads / History
Entry: `Sources/FaceHugger/MainView.swift` (MainView, JobRow, JobInspector)

```text
- Sources/FaceHugger/FaceHuggerApp.swift (scene and menu commands)
  - Sources/FaceHugger/MainView.swift (common shell and presentation)
    - Sources/FaceHugger/RepoBrowser.swift (alternate shell destination)
    - Sources/FaceHugger/Sheets.swift (UploadSheet, SettingsSheet, CreateRepoSheet, ErrorBanner)
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
  - Resources/Assets.xcassets/Hugger.imageset/hugger.png
```

## Repository browser
Entry: `Sources/FaceHugger/RepoBrowser.swift` (RepoBrowser)

```text
- Sources/FaceHugger/FaceHuggerApp.swift (scene and menu commands)
  - Sources/FaceHugger/MainView.swift (common shell and presentation)
    - Sources/FaceHugger/RepoBrowser.swift (RepoBrowser)
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
```

## New upload sheet
Entry: `Sources/FaceHugger/Sheets.swift` (UploadSheet, ErrorBanner)

```text
- Sources/FaceHugger/FaceHuggerApp.swift (scene and menu commands)
  - Sources/FaceHugger/MainView.swift (common shell and presentation)
    - Sources/FaceHugger/Sheets.swift (UploadSheet, ErrorBanner)
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
  - Resources/Assets.xcassets/Hugger.imageset/hugger.png
```

## Settings sheet
Entry: `Sources/FaceHugger/Sheets.swift` (SettingsSheet, ErrorBanner)

```text
- Sources/FaceHugger/FaceHuggerApp.swift (scene and menu commands)
  - Sources/FaceHugger/MainView.swift (common shell and presentation)
    - Sources/FaceHugger/Sheets.swift (SettingsSheet, ErrorBanner)
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
```

## Create repository sheet
Entry: `Sources/FaceHugger/Sheets.swift` (CreateRepoSheet, ErrorBanner)

```text
- Sources/FaceHugger/FaceHuggerApp.swift (scene and menu commands)
  - Sources/FaceHugger/MainView.swift (common shell and presentation)
    - Sources/FaceHugger/Sheets.swift (CreateRepoSheet, ErrorBanner)
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
```

## Menu bar
Entry: `Sources/FaceHugger/FaceHuggerApp.swift` (MenuContent)

```text
- Sources/FaceHugger/FaceHuggerApp.swift
  - Sources/FaceHugger/AppModel.swift (shared observable state/actions)
    - Sources/FaceHuggerCore/Models.swift (HubRepo, UploadJob, UploadProgress, validation, archive)
    - Sources/FaceHuggerCore/UploadQueueControl.swift (scheduler)
      - Sources/FaceHuggerCore/Models.swift
    - Sources/FaceHugger/Services.swift (runtime paths, credentials, subprocess, Hub API bridge, remote entries)
      - Resources/bridge.py (bundled runtime resource; not Swift import)
      - requirements.txt (runtime dependency pin)
  - Sources/FaceHugger/MainView.swift (Show Face Hugger opens existing main scene)
    - Sources/FaceHugger/RepoBrowser.swift
    - Sources/FaceHugger/Sheets.swift
    - Resources/Assets.xcassets/Hugger.imageset/hugger.png
```
