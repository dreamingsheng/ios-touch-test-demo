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
| Native 4.1 local test package | `C:\Users\admin\Downloads\TouchTest-v4.1-native-run42223596432-unsigned.ipa`, build 25, 9,983,278 bytes, SHA-256 `2c92a506bf93c83f8235a209dfc0755b2d43a2cf80f46d11fcf9411bdf0a0728` | CRC/checksum/version verified; native entry and Media resources, no HTML application. This is a candidate, not a claim that every UI check passed |
| Native 4.1 build 28 local candidate | `C:\Users\admin\Downloads\TouchTest-v4.1-build28-native-unsigned.ipa`, 9,989,656 bytes, SHA-256 `f5fea97330228c09c73d731374dfbf354174675bc8a59fb1f52f50f604cb38cb` | CRC/checksum/version/native-entry verified. Seven of eight UI cases passed; project-menu drag failed. Do not treat it as a fully validated release |
| Packaged functionality | Compiled-bundle verifier checks device families, four directions, executable and hashes of all bundled scenario/media files | Does not exercise touch hardware |
| Browser interaction logic | `tests/browser-regression.cjs`: real pointer touch, coalesced sample geometry, pinch anchor, cancellation, stationary hold, menu state, MP4 decode, exports and bounded recording | Desktop Chromium touch emulation; cannot certify UIKit/Safari behavior on every iOS release |
| Offline operation | Offline reload plus actual 206 byte-range reads from the bundled MP4 | Files/share acceptance remains a physical-device task |
| Initial native layout | Earlier simulator evidence for iPhone 16e and iPad Pro 13-inch (M5), portrait and landscape | Earlier checks opened the default multi-touch screen only |
| Expanded native inspection | `scripts/simulator-smoke.py` plus debug-only native command/evidence bridge now open all 21 scenes in both orientations | Current run must actually complete and its screenshots must be inspected before marking this row passed |

## Current verification record

- Native 4.0 run `42218978046` completed successfully, including five real XCTest UI cases and three simulator categories.
- Native 4.1 run `42223596432` compiled successfully and all three simulator categories passed 46 cases each. Tests compare actual scene rectangles converted into UIWindow coordinates, hidden system status bar, and safe floating project/clear buttons. Automatic game landscape tests first return to portrait. The original images are retained; review previews rotate/resize copies only.
- In that first 4.1 run, six of seven real UI tests passed. The fixed-window-endpoint recheck `42227175463` confirmed that the HUD short-drag defect was real, rather than only a test-endpoint problem. Raw touch-down anchors fixed the HUD displacement and persistence: this case passed in runs `42229585413` and `42232908399` without relaxing its tolerance. Those runs passed seven of eight cases; the additional floating project-menu drag still failed. A subsequent fix captures every new single-touch anchor without assuming the recognizer's tracked-touch count is zero, and retains failure diagnostics.
- Inspected 4.1 iPhone 16e previews for photo, vertical reading, MOBA and shooter. Native white fullscreen and initial gameplay were also inspected from the preceding 4.0 artifacts. This does not establish every screenshot's visual fidelity.
- Web v16 is deployed. All 30 cases passed against the actual public URL, including real media time/frame advancement, error/retry feedback, stale VisualViewport-height recovery and capability-based fullscreen behavior. The user confirmed the reported lower black gap occurs in a Safari tab. Physical verification in that opening mode remains required; CSS cannot hide Safari's own toolbars.
- A diagnostic correctness patch adds measured tap last/average/maximum error, reachable target placement outside visible floating controls, coverage reset after real geometry changes, and cross-cursor remapping. Three real input/rotation UI tests supplement the original eight. These new checks require their own macOS CI result before being called passed.
- Run `42232908399` is terminal: device build and all three 46-case simulator categories passed; native UI was 7/8 and public publishing was skipped. Its build 28 is retained locally as a candidate. The failed menu-drag check must pass in a later run before replacement is presented as validated.
- User additions are preserved: substantially more MOBA interaction locations; changeable, initially smaller photos; vertical reading by default; default visible clear actions; matching web updates. The user clarified that the image-size/default-image request concerns the photo test.

## Not yet established

The IPA now uses UIKit/AVFoundation throughout the main 21-scene entry. Earlier web-wrapper results do not prove this native implementation. Browser evidence remains separate from native evidence.

1. A fully passing current native UI result, followed by review of the corresponding build's simulator artifacts and public release replacement. Earlier successful geometry checks do not establish later interaction changes.
2. Visual comparison against agreed, version-specific original screens for a one-to-one claim. Generated game backgrounds, a fictitious offline map and local sample video are not originals of the referenced commercial applications.
3. Physical-device fullscreen, keyboard, exported-file handling, simultaneous finger behavior, interruption recovery and the user's reported border/occlusion issue.
4. A verified result for every supported physical model and iOS version. Current deployment target is iOS 16+, not every historical iPhone.

The goal remains uncompleted until the remaining evidence is obtained. Simulator inspection verifies presentation and loading; it does not replace real touchscreen operation.
