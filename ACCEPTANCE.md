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
| Packaged functionality | Compiled-bundle verifier checks device families, four directions, executable and hashes of all bundled scenario/media files | Does not exercise touch hardware |
| Browser interaction logic | `tests/browser-regression.cjs`: real pointer touch, coalesced sample geometry, pinch anchor, cancellation, stationary hold, menu state, MP4 decode, exports and bounded recording | Desktop Chromium touch emulation; cannot certify UIKit/Safari behavior on every iOS release |
| Offline operation | Offline reload plus actual 206 byte-range reads from the bundled MP4 | Files/share acceptance remains a physical-device task |
| Initial native layout | Earlier simulator evidence for iPhone 16e and iPad Pro 13-inch (M5), portrait and landscape | Earlier checks opened the default multi-touch screen only |
| Expanded native inspection | `scripts/simulator-smoke.py` plus debug-only native command/evidence bridge now open all 21 scenes in both orientations | Current run must actually complete and its screenshots must be inspected before marking this row passed |

## Current verification record

- Native 4.0 run `42218978046` completed successfully, including five real XCTest UI cases and three simulator categories.
- Native 4.1 run `42223596432` compiled successfully and all three simulator categories passed 46 cases each. Tests compare actual scene rectangles converted into UIWindow coordinates, hidden system status bar, and safe floating project/clear buttons. Automatic game landscape tests first return to portrait. The original images are retained; review previews rotate/resize copies only.
- In that 4.1 run, six of seven real UI tests passed: native game settings/landscape, real two-finger sampling and clearing, smaller/changeable photo/pinch/reset retaining selection, default vertical reader, native settings, and native keyboard avoidance. HUD drag displacement failed its exact assertion. The test endpoint was bound to the moving HUD element; run `42227175463` rechecks fixed window endpoints with the original displacement tolerance and test-only native pan diagnostics. Its result must be observed before calling that check passed.
- Inspected 4.1 iPhone 16e previews for photo, vertical reading, MOBA and shooter. Native white fullscreen and initial gameplay were also inspected from the preceding 4.0 artifacts. This does not establish every screenshot's visual fidelity.
- Web v15 is deployed. The updated regression passed all 29 cases against the actual public URL, including real media time/frame advancement, error/retry feedback and a stale VisualViewport-height fixture that must not shorten a non-keyboard canvas. iPhone Safari/PWA physical verification of the reported lower black gap is still required.
- User additions are preserved: substantially more MOBA interaction locations; changeable, initially smaller photos; vertical reading by default; default visible clear actions; matching web updates. The user clarified that the image-size/default-image request concerns the photo test.

## Not yet established

The user's new acceptance correction supersedes the earlier IPA architecture: the IPA must be a normal native application, with an edge-to-edge test surface, no top/bottom letterboxing, default landscape game entry, a floating joystick, movable HUD/menu and saved positions. The 4.0 source now uses UIKit/AVFoundation throughout the main 21-scene entry. Its build/simulator/device evidence must be obtained independently; the old 3.0 checks do not prove the native replacement.

Web v13 is a separate deliverable. Its 25-check CDP regression passed, including a full-window canvas, safe floating controls, real two-finger floating joystick operation, HUD editing/persistence and all project-menu entries. This evidence applies to Chromium emulation only.

1. The new 4.0 native build, all 21 native scene screenshots on each of the three simulator categories, actual hidden status bar, full-window canvas and automatic game landscape entry.
2. Visual comparison against agreed, version-specific original screens for a one-to-one claim. Generated game backgrounds, a fictitious offline map and local sample video are not originals of the referenced commercial applications.
3. Physical-device fullscreen, keyboard, exported-file handling, simultaneous finger behavior, interruption recovery and the user's reported border/occlusion issue.
4. A verified result for every supported physical model and iOS version. Current deployment target is iOS 16+, not every historical iPhone.

The goal remains uncompleted until the remaining evidence is obtained. Simulator inspection verifies presentation and loading; it does not replace real touchscreen operation.
