# First-run verification on your Mac / iPhone

These are manual checks to perform; they were not executed in the Linux authoring environment.

- [ ] Open project; build Forma Local on Simulator and device SDK.
- [ ] Build Forma Health on Simulator/device with a compatible signing profile.
- [ ] Run XCTest from Product → Test.
- [ ] Log a half-serving at a past date/time; edit it and confirm totals.
- [ ] Import the included CSV; re-import and verify catalog updates rather than duplicate matches.
- [ ] Import an invalid CSV and verify no partial catalog mutation.
- [ ] Edit a food and verify an older log keeps its original nutrition.
- [ ] Create/reorder/delete a routine and exercise; retain at least one exercise to save.
- [ ] Start workout, edit loads/reps, flag warm-up/failure, start and complete sets.
- [ ] Background/terminate/reopen during a workout; resume saved session.
- [ ] Disable timers and verify countdown and pending rest alert are removed.
- [ ] Start/complete/adjust a set from Lock Screen and expanded Dynamic Island.
- [ ] Tap Log twice quickly; verify only the addressed set completes once.
- [ ] Finish/discard from the app; verify Live Activity ends.
- [ ] Finish a later stronger session; verify records and exclusion of warm-ups.
- [ ] Log sleep and manual weight; verify same-day chart pairing.
- [ ] Sync Health twice; energy must not double. Try denied access and no-sample days.
- [ ] Test CSV and JSON selection from Files and backup export/restore.
- [ ] Verify malformed/future-version backup rejection without replacing current data.
- [ ] Test UMass when its server is operational; compare several imported recipes with the published page.
- [ ] Test offline logging and a failed UMass refresh; preserve the existing catalog.
- [ ] Check large Dynamic Type, VoiceOver, light/dark appearance, and keyboard use on iPhone 15 Pro.
- [ ] Install the IPA via Sideloadly with the extension retained; test signing renewal without deleting app data.
