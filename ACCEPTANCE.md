# Acceptance ledger

This ledger preserves the requested scope. It does not turn browser or simulator checks into physical touchscreen certification.

## Required outcome

- Free public browser entry and a signable IPA in the Windows Downloads folder.
- Drawing, line following, ghost-touch observation, target following, coverage grid, edges, photo/map gestures, reading, video feed, MOBA, shooter, settings, typing, dual-axis, tap/hold and display patterns.
- Black/white diagnostic shell; reference-based game/application layouts and working visible controls.
- Transparent/fullscreen presentation with no obscured controls at the notch, Dynamic Island or home indicator, in portrait/landscape on supported iPhone/iPad models.
- Actual browser/native input sampling, reproducible results and export, with limitations stated accurately.
- Inspect the app in simulators before publicly replacing the test IPA.

## Evidence already established

| Requirement | Authoritative evidence | Boundary |
| --- | --- | --- |
| Public browser entry | GitHub Pages application and public-URL regression runs | User's Safari/PWA cache and system chrome still need affected-device confirmation |
| Local signable test package | `C:\Users\admin\Downloads\TouchTest-v3.0-run42209956934-unsigned.ipa`, 9,909,617 bytes, SHA-256 `c102f483f028d41fbd2e592a8ce2fbf71e0dee343f0082fa0c2486dbaa3a2873` | This is the earlier user-requested local test package, not a claim that all simulator categories passed |
| Packaged functionality | Compiled-bundle verifier checks device families, four directions, executable and hashes of all bundled scenario/media files | Does not exercise touch hardware |
| Browser interaction logic | `tests/browser-regression.cjs`: real pointer touch, coalesced sample geometry, pinch anchor, cancellation, stationary hold, menu state, MP4 decode, exports and bounded recording | Desktop Chromium touch emulation; cannot certify UIKit/Safari behavior on every iOS release |
| Offline operation | Offline reload plus actual 206 byte-range reads from the bundled MP4 | Files/share acceptance remains a physical-device task |
| Initial native layout | Earlier simulator evidence for iPhone 16e and iPad Pro 13-inch (M5), portrait and landscape | Earlier checks opened the default multi-touch screen only |
| Expanded native inspection | `scripts/simulator-smoke.py` plus debug-only native command/evidence bridge now open all 21 scenes in both orientations | Current run must actually complete and its screenshots must be inspected before marking this row passed |

## Not yet established

1. All 21 native scene screenshots passing on each of the three selected simulator categories.
2. Visual comparison against agreed, version-specific original screens for a one-to-one claim. Generated game backgrounds, a fictitious offline map and local sample video are not originals of the referenced commercial applications.
3. Physical-device fullscreen, keyboard, exported-file handling, simultaneous finger behavior, interruption recovery and the user's reported border/occlusion issue.
4. A verified result for every supported physical model and iOS version. Current deployment target is iOS 16+, not every historical iPhone.

The goal remains uncompleted until the remaining evidence is obtained. Simulator inspection verifies presentation and loading; it does not replace real touchscreen operation.
