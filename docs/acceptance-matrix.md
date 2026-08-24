# Acceptance Matrix

Validated on 2026-08-24 against Hyprland 0.56.2. The aggregate command is
`./scripts/verify-release`; every automated evidence item below is part of that
gate. Fixture and fake-compositor checks are intentionally used for disruptive
failure cases so release verification does not alter the live desktop.

## Windows-like acceptance scenarios

| # | Scenario | Evidence | Result |
|---:|---|---|---|
| 1 | Never-seen monitor gets a safe layout without disturbing other profiles | `tests/profile-store.test.sh`, `tests/profile-management.test.sh`, preset fallback tests in `tests/topology-model.test.js` | Pass (automated) |
| 2 | Known monitor on the same connector restores exact topology and enabled state | v2 exact restore in `tests/profile-store.test.sh` and full topology round-trip in `tests/apply-layout.test.sh` | Pass (automated) |
| 3 | Strongly identified monitor moved to another connector is revalidated and confirmed | moved-match, fork, and update cases in `tests/profile-store.test.sh` and `tests/profile-matching.test.js` | Pass (automated) |
| 4 | Identical serial-less monitors never silently swap | ambiguous tie cases in `tests/profile-matching.test.js`; Keep guard and Identify UI lint/static audit | Pass (automated) |
| 5 | Unplug during preview cancels safely and retains a usable display | stale hot-plug recovery cases in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |
| 6 | Two dock events 500 ms apart are coalesced | deterministic quiet-window sequence in `tests/display-events.test.js` | Pass (automated clock) |
| 7 | Runtime link/GPU resource conflict is actionable | forced compositor rejection in `tests/apply-layout.test.sh` plus reason-code checks in `tests/topology-model.test.js` | Pass (automated fake compositor) |
| 8 | Unlike clone targets use a disclosed common mode | common-mode table and rejection tests in `tests/topology-model.test.js`; mirror apply/revert in `tests/apply-layout.test.sh` | Pass (automated) |
| 9 | Rotated mixed-DPI scale changes preserve logical geometry | rotated logical-size, seam, and settings tests in `tests/topology-model.test.js` and `tests/layout-model.test.js` | Pass (automated) |
| 10 | Rightmost anchor preserves negative left/top coordinates | anchor/focus tests in `tests/topology-model.test.js` and persisted signed coordinates in `tests/profile-store.test.sh` | Pass (automated) |
| 11 | Rejected or timed-out risky modes restore exact prior topology | bad-mode, Revert, watchdog, and mirrored-group rollback cases in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |
| 12 | Wireless/virtual target appears only after driver enumeration | unknown `Virtual-1` enumeration in `tests/monitor-snapshot.test.sh`; arrangement consumes only enumerated records | Pass (automated fixture) |
| 13 | Brief EDID/KVM identity loss never deletes or overwrites a saved profile | observation-only mismatch and retained migration/profile state in `tests/profile-store.test.sh`; weak/ambiguous matcher cases | Pass (automated) |
| 14 | Connector changes during Apply/Keep abort stale assumptions | hardware-generation rejection and stale-cancel tests in `tests/apply-layout.test.sh` | Pass (automated fake compositor) |

## Validation scope

Automated validation passed using sanitized monitor fixtures. Physical
hot-plug, dock, projector, pointer-seam, and live-preview scenarios still
require manual verification on representative hardware.
