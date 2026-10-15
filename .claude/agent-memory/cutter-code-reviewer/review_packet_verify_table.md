---
name: review-packet-verify-table
description: The cutter-verify table in a /cutter:work review packet is the previous run, not HEAD's; do not flag it as stale
metadata:
  type: project
---

In `/cutter:work` Step 6/7a the caller starts `cutter-verify` in the background in the same message that spawns reviewers, so the packet's "Last cutter-verify run" usually shows an older HEAD than the packet's branch tip.

**Why:** verify and review run concurrently by design; the fresh table goes to the caller, not the reviewer.

**How to apply:** note the HEAD mismatch in Verification only; never raise it as a finding or blocker, and do not re-run the suite to compensate.
