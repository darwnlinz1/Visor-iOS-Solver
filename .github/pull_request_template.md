## What & why

<!-- What does this PR change, and why? List the PLAN.md tasks (Tx.y). Link any issue it closes: "Closes #123". -->

## How it was tested

<!-- On-device? Which iPhone / iOS / glasses firmware? Which model? Steps you ran. -->
- [ ] `make blueprint-check` (static guard) reports 0 failed
- [ ] Touched `OpenVision/Services/Speech/` → `scripts/swift-local/run.sh` passes
- [ ] CI and E2E are green on the last commit; every new suite shows an "Executed" line in the E2E log
- [ ] Verified the specific behavior this PR changes (exact-output tests)
- [ ] Touched the solver / voice / photo / reading flow → hardware steps run or listed for the owner
      (`PLAN.md` §7, H1–H22; the simulator can't do Bluetooth or the glasses)

## Checklist

- [ ] Code matches the style of the surrounding files (naming, comments, idioms)
- [ ] No secrets, API keys, or personal data committed or logged
- [ ] Added/removed Swift files registered with `scripts/pbxproj_files.py` (not `xcodegen generate`)
- [ ] Commits: `Type: …` (≤ 72 chars) + `Task: Tx.y`, one commit per task
- [ ] Audio invariants kept (`PLAN.md` §0 rule 7)
- [ ] Updated docs if behavior changed (`PLAN.md` status, README, CHANGELOG)

## Notes for reviewers

<!-- Anything tricky, follow-ups, hardware steps still needed ("Cần chủ dự án chạy H…"). -->
