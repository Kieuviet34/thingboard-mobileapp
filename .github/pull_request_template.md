## What and why
<!-- One or two sentences. Link the issue/plan if there is one. -->

## How it was verified
<!-- Paste real output; "should work" is not verification. -->
- [ ] `dart format --output=none --set-exit-if-changed .`
- [ ] `flutter analyze --fatal-infos` — 0 issues
- [ ] `flutter test --coverage` — all pass (count: )
- [ ] `flutter build apk --debug` (when Android/plugins/manifest changed)

## API changes (delete if none)
- [ ] New/changed endpoint is covered by a contract test under `test/core/api/repositories/contract/`
- [ ] `python -I tools/api_contract/build_subset.py --spec <openapi.json>` re-run and snapshot committed
- [ ] Any deviation from the ThingsBoard spec is listed in `tools/api_contract/known_deviations.json` with a reason

## UI changes (delete if none)
- [ ] Light and dark checked; text scale 2.0x has no overflow
- [ ] Smallest (320dp) and largest phone, landscape, and tablet checked
- [ ] Tap targets >= 48dp, `Semantics`/tooltips on icon-only controls, reduced motion honored
- [ ] Screenshots attached

## Risks / follow-ups
