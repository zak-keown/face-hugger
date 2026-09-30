# Extractable native UI patterns

These are candidates for visual DraftComponent extraction, not existing React components. Keep SwiftUI as the implementation target. Native controls remain platform controls. Only state/navigation/count props below are proposed draft props; model content remains represented by realistic fixtures unless the selected draft needs it.

## AppShell
- Source: `Sources/FaceHugger/MainView.swift`
- Category: layout
- Description: Sidebar, toolbar and split content with optional inspector.
- Extractable props: activeItem (string, default uploads); showInspector (boolean)
- Hardcoded: Native split geometry, traffic-light chrome, New Upload label and icon, toolbar style

## Sidebar
- Source: `Sources/FaceHugger/MainView.swift`
- Category: layout
- Description: Upload/history navigation, repo list, owner switch and account footer.
- Extractable props: activeItem (string); pendingCount (integer); isConnected (boolean); isLoading (boolean); showOwnerPicker (boolean)
- Hardcoded: Uploads/History/Repositories labels, SF Symbols, account/settings footer placement

## QueueFooter
- Source: `Sources/FaceHugger/MainView.swift`
- Category: layout
- Description: Shared queue/history footer showing activity and keep-awake state.
- Extractable props: isUploading (boolean); uploadCount (integer); isHistory (boolean); keepAwake (boolean)
- Hardcoded: Status icons, padding, captions, window-close explanation

## JobRow
- Source: `Sources/FaceHugger/MainView.swift`
- Category: basic
- Description: Reusable upload/history item with folder, state, destination and activity.
- Extractable props: jobState (string); isSelected (boolean)
- Hardcoded: Folder symbol and blue tint, typography, indeterminate running progress pattern

## JobInspector
- Source: `Sources/FaceHugger/MainView.swift`
- Category: layout
- Description: Selected job metadata, stage counters, actions and activity log.
- Extractable props: jobState (string); showProgress (boolean); showLog (boolean)
- Hardcoded: From/To/Repository/Added labels, action icons, log monospace, pane geometry

## ErrorBanner
- Source: `Sources/FaceHugger/Sheets.swift`
- Category: basic
- Description: Dismissible inline error shared across sheets.
- Extractable props: isVisible (boolean)
- Hardcoded: Warning icon, orange color, quaternary rounded background, dismiss icon

## SheetActionBar
- Source: `Sources/FaceHugger/Sheets.swift`
- Category: basic
- Description: Repeated native modal footer pattern, currently inline in each sheet.
- Extractable props: isBusy (boolean); canSubmit (boolean)
- Hardcoded: Native Cancel placement, primary button style; each concrete sheet keeps its action labels

## MenuContent
- Source: `Sources/FaceHugger/FaceHuggerApp.swift`
- Category: layout
- Description: Menu bar status with stop/show/quit controls.
- Extractable props: isUploading (boolean)
- Hardcoded: Menu labels, separators, shortcut and native menu styling

RepositoryHeader and breadcrumb are screen-local in RepoBrowser.swift, not shared components today. No custom Button/Input/Card/Tab primitives exist to extract. Do not invent a card dashboard or substitute a browser UI for the macOS window.
