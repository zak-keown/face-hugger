# Face Hugger: redesign exploration

September 30, 2026. Transfer Bench is the selected direction. These are design prototypes, not implemented features.

The first app established the upload machinery but gave the user a generic queue, an inspector, and a long configuration form. The approved mascot carried almost all of the personality. The redesign starts with the relationship between a local folder and its remote destination.

## Transfer Bench

Two aligned file surfaces fill the window. The left shows the chosen folder on this Mac; the right shows the destination repository and folder. A small gold directional element connects their headers. A slate-blue activity shelf remains visible below both surfaces.

Dropping a folder populates staging in place. Choosing a repository updates the remote file pane. Filters open on demand and affect the staging preview. A review strip shows the selected destination, visibility, and matching remote paths before the explicit Upload action. History and logs belong in the activity shelf rather than separate navigation destinations.

This is the recommended direction: it gives both uploading and limited remote management a coherent place in the same window.

## Earlier alternative: Dispatch

A narrow rail stores named local-folder/remote-repository pairings. The main workspace shows one transfer manifest with Files, Activity, and Remote views. This suits repeated checkpoint uploads with the same destination and filters. Uploads remain manual; a saved pairing is not automatic synchronization.

The permanent rail was not selected. Saved pairings are carried into Transfer Bench as a compact toolbar popover.

## Approved state pass

The selected prototype keeps the same window and changes state through clearly separated preview controls. Sample files and actions never touch an account.

| State | Workspace | Activity shelf | Main action |
| --- | --- | --- | --- |
| First upload | Choose/drop local folder; remote repository remains browsable | Collapsed, no transfers yet | Choose folder; Upload disabled |
| Ready | Staged file list, visible private destination, one path collision | Quiet until upload starts | Upload 4 files |
| Running | Browsing stays available | Concurrent stage counts and sample log | Stop upload |
| Stopped this session | Source and destination remain visible | Last-reported counts, no live indicator | Resume upload |
| Recovered after relaunch | Persisted route and interrupted status | No invented retained counters or logs | Resume after checking source availability |

Saved pairings belong in a small toolbar popover. Choosing one restores both endpoints and filters, never starts a transfer, and must not silently discard unsent work. Dark mode keeps identical layout while separating warm graphite source, cooler remote surface, and recessed slate shelf. Gold remains reserved for direction and the primary action.

## Design commitments

- Preserve the approved mascot, at a useful identity scale rather than as a giant empty-state illustration.
- Use a deliberate SF Pro type scale, aligned file columns, and readable metadata.
- Keep file surfaces continuous. Avoid dashboard cards and ornamental borders.
- Give local files a warm porcelain surface and remote files a cool white surface, anchored by slate and restrained gold. A native dark appearance needs equal attention before implementation is complete.
- Show preparation, upload/reuse, and committed counts as concurrent activity. No invented overall percentage or ETA.
- Keep Stop and Resume semantics, repository visibility, keyboard interaction, and confirmations for remote deletion.

## Implementation implications

Local staging needs cancellable background enumeration and the same filter semantics as the pinned CLI. Matching-path indicators report path collisions, not content equality. Recursive remote checks must remain responsive and must not block browsing. Saved pairings persist configuration, never tokens, and uploads continue to require an explicit action. Returning to a completed upload should lead directly to its remote contents.

Validation can use small synthetic trees, many-file fixtures, controlled subprocesses, and bounded interrupted uploads. Multi-terabyte disk capacity is not a prerequisite or a planned acceptance requirement.

## Prototype verification

Revision 5 was inspected in Safari in light and dark appearance. The Choose folder → Upload → Stop → Resume flow, recovery without retained counters, and pairing confirmation/update passed native browser interaction checks. The recovery message was widened after visual review found clipping. The prototype uses fixed sample files; account controls and file-selection changes are explicitly disabled. The local copy is `.superdesign/transfer-bench.html`; no native app behavior changed in this design pass.
