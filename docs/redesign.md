# Face Hugger: Transfer Bench redesign

September 30, 2026. Transfer Bench is now implemented in the native SwiftUI app. The [interactive prototype](https://p.superdesign.dev/draft/3f6d6851-b4e3-4d68-a1bf-f8a378ccad65) remains the approved visual reference. See [design and asset provenance](design.md), [verification record](verification.md), and the [design canvas](https://superdesign.dev/teams/d6bf7272-b808-4594-89cb-9ed77f64920c/projects/016e36f9-f366-4c98-836f-c9bbf5783746).

The first app established the upload machinery but separated the queue, repository browser, inspector, and long upload form. Transfer Bench puts the local folder and remote destination in the same working context.

## Implemented workflow

Two file surfaces share the window: local staging on the left, repository browsing on the right. A small gold directional element connects their headers, and a slate activity shelf spans the bottom. The toolbar holds the approved mascot, account settings, and saved pairings. There is no permanent sidebar.

Choosing or dropping a folder starts a cancellable preview scan. Include/exclude filters update the staged list and measured file/byte totals. The preview can be truncated while totals cover the full scan. A searchable repository picker supports account/organization repositories and explicit repository IDs. Folder navigation and a destination sheet choose where uploads go, including a not-yet-created subfolder.

Upload is explicit; when another transfer is active, the main action queues the new job. Submission rechecks repository visibility and rejects a stale workspace configuration. The review strip gives a general replacement warning; the local table compares exact remote paths without content-equality claims.

Saved pairings persist the source, repository, destination path, and filters, never tokens. Selecting one restores configuration without starting an upload and asks before replacing an already prepared source. Pairings can be saved and removed; search, rename, and active-pairing indication remain future polish.

## Native states

| State | Workspace | Activity shelf / action |
| --- | --- | --- |
| First upload | Choose/drop a folder; select or browse remote destination | 64 pt empty shelf; Upload disabled until ready |
| Ready | Included/excluded file preview, measured totals, visible destination | Explicit Upload or Add to queue |
| Running | Browsing and staging remain available | Concurrent reported preparation, upload/reuse, and commit counts; Stop upload |
| Stopped this session | Prepared workspace remains | Last-reported counters where available; Resume upload |
| Recovered after relaunch | Persisted job route is shown in the shelf | Interrupted state without invented retained counters/logs; resume validates source |
| Completed | Current remote destination is refreshed when applicable | Completion state, date, and link to Hugging Face |

The shelf's Transfers popover holds queue/history selection, ordering, removal, and a route back to the active job. Activity logs are available only for the current session. A missing source offers Locate folder; choosing a replacement prepares the workspace and leaves the job stopped.

## Visual implementation and boundaries

Adaptive source/remote colors support light and dark system appearance; the activity shelf stays dark in both. The native window uses SF Pro, native tables and menus, a small identity mascot, and gold directional/primary-action accents. The two panes expand with the window but do not have a draggable divider. The prototype's external state selector and appearance switch are not native app controls.

Ancestor-path conflicts, content-equality checks, automatic synchronization, retained session logs/counters, and selecting uploaded files after completion are not implemented. Local/remote header and row alignment, filter-empty feedback, and explicit accessibility labels should be verified in native UI review rather than inferred from the prototype.

## Design history and verification

The alternate Dispatch concept proposed a permanent saved-pairing rail and a transfer manifest. That structure was not selected; its reusable pairings became the toolbar popover.

Prototype revision 5 was inspected in Safari in light and dark appearance. Its Choose folder → Upload → Stop → Resume flow, recovery without retained counters, and pairing confirmation/update passed browser interaction checks. The recovery message was widened after clipping was found. The prototype uses fixed sample files and cannot alter an account; its local copy is `.superdesign/transfer-bench.html`.

The native redesign builds successfully. Prototype interaction checks are not evidence of native end-to-end validation; current test and live-smoke evidence belongs in [verification.md](verification.md). Validation can use small synthetic trees, many-file fixtures, controlled subprocesses, and bounded interrupted uploads. Multi-terabyte disk capacity is not a prerequisite.

File-status follow-up: the native local table now shows New path, Remote path exists, Excluded, or Not checked. This compares previewed paths only, without content equality or ancestor-conflict claims. Missing-source jobs support Locate folder and manual resume; likely account/network failures show recovery guidance.
