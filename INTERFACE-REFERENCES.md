# Interface reference and fidelity audit

The request is to match real applications, including the controls, feedback and fullscreen behavior. A generated environment image is not evidence of one-to-one UI fidelity.

## Primary references inspected

- [Google Android CTS Verifier](https://android.googlesource.com/platform/cts/+/master/apps/CtsVerifier/): manual hardware verification and independent touch contacts.
- [MultiTouch Test developer listing and screenshots](https://play.google.com/store/apps/details?id=com.easylabs.multitouch): colored numbered contacts, pointer coordinates, pointer count and display information.
- [Android Touch Sample Rate Tester](https://github.com/samnyan/Android-Touch-Sample-Rate-Tester): event-rate display and screenshot; browser-delivered sampling is still different from kernel/controller sampling.
- [Touchpaint for Android](https://github.com/kdrag0n/touchpaint-android): continuous paint, tap fill and follower interaction concepts.
- [Tencent Honor of Kings open environment](https://github.com/tencent-ailab/hok_env): independent movement/skill controls and gameplay/action semantics.
- Developer-provided App Store materials: [Honor of Kings](https://apps.apple.com/cn/app/id989673964), [Game for Peace](https://apps.apple.com/cn/app/id1321803705). Store images at inspection were predominantly promotional material, not a complete baseline for every gameplay control. Lookup reported versions 12.1.1.1 and 1.38.12 respectively; these numbers do not prove that a gameplay screenshot represents those releases.
- [Apple safe-area/rotation APIs](https://developer.apple.com/documentation/uikit/uiview/safeareainsets): native frame geometry is read on device and forwarded to the bundled page.

## Current implementation and remaining evidence

| Area | Implemented | Still required for a one-to-one claim |
| --- | --- | --- |
| Touch diagnostics | Browser event samples, ordered contacts, full coordinate axes, traces, coverage, stationary hold, monitoring and export | Side-by-side comparison to an agreed target test-app screen, plus real-device sampling |
| MOBA | Fullscreen scene texture, arced skill positions, movement stick, independent held skills, directional cast indicator, attack and utility buttons | Agreed game release/hero/key-layout baseline and icon-by-icon/feedback comparison |
| Shooter | Training-world texture, movement, drag aiming, fire, ammo indicator and stance controls | Agreed game release/key layout, exact weapon/scope/camera behavior and all ancillary controls |
| Photo/map | Photograph pinch anchor; vector street map, search, locate, favorite and route interactions | Exact selected photo/map application's reference screens and transition comparison |
| Short-video | Actual bundled MP4 playback, seek/pause, feed swipe, per-item likes, comments, share/profile/search/list controls | Exact target release's full tab/page baseline; offline test content is not a live service |
| Settings/reader/input | Multi-level navigation, persisted options within the scene, switches/sliders, reader pages/font sizing, actual platform text entry | Full visual comparison to a selected application/version and iPhone keyboard acceptance |
| Fullscreen | Transparent background, a single safe content frame, native UIKit safe-area bridge, manual margin adjustment | Passing current simulator artifacts and physical-device checks on the user's affected device |

## Media

The three generated raster assets are listed in [IMAGE-PROMPTS.md](IMAGE-PROMPTS.md). The video is an actual CC0 MDN sample. The city map is an original offline vector test map with fictitious locations. None is presented as an extracted original game/application screen.
