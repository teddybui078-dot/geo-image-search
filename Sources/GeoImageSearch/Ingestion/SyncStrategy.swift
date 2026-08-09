import Foundation

// Next Step 1a — one-shot full ingest vs. incremental new/deleted-asset diff on relaunch.
enum SyncStrategy {
    case fullIngest
    case incrementalDiff
}
