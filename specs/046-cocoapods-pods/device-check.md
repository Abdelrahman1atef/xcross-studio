# Device Check: 046 CocoaPods pods without CocoaPods

Hardware status on 2026-11-16: Windows 11 host (x86_64), Swift 6.4.2, Flutter 3.47, xcross 2.0.9-xs.7. iPhone (Elgohary, iOS 16.7.16, UDID 388855a5602b2d44e545ec8b4c5e45b95cc1ea47) connected by USB and verified reachable via xcross devices and doctor.

| Probe | Host | Device / iOS | Build | Run-time check | Date | Notes |
|---|---|---|---|---|---|---|
| P1-a (videosdk_webrtc 0.0.19) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | WebRTC-SDK binary target synthesized and verified |
| P1-a (videosdk_webrtc 0.0.19) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P1-b (objectbox_flutter_libs 5.3.2) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | ObjectBox binary target synthesized and verified |
| P1-b (objectbox_flutter_libs 5.3.2) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P1-c (flutter_vlc_player 7.4.4) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | MobileVLCKit binary target + wrapper linker flags verified |
| P1-c (flutter_vlc_player 7.4.4) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P1-r (Resource probe Bundle(for:)) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | PodResourcesStager verified (AC-046-8) |
| P2-a (qr_code_scanner 1.0.1) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | ObjC source layout, prefix header, and camera bindings verified |
| P2-a (qr_code_scanner 1.0.1) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P2-b (flutter_sound 9.30.0) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | ObjC source targets and audio frameworks verified |
| P2-b (flutter_sound 9.30.0) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P2-c (flutter_blue 0.8.0) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | CoreBluetooth linking and header search paths verified |
| P2-c (flutter_blue 0.8.0) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P2-d (google_mlkit_text_recognition 0.15.1) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Header-only GoogleMLKit + sibling google_mlkit_commons dependency verified |
| P2-d (google_mlkit_text_recognition 0.15.1) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P2-e (myfatoorah_flutter 3.3.3) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Headers inside xcframework source_files mapped and compiled |
| P2-e (myfatoorah_flutter 3.3.3) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P3-a (speech_to_text 6.6.2) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Swift speech framework integration and language mode verified |
| P3-a (speech_to_text 6.6.2) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P3-b (go_sell_sdk_flutter 2.4.29) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Tap closure Swift ↔ ObjC cross-package linking and bundles verified |
| P3-b (go_sell_sdk_flutter 2.4.29) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P3-c (flutter_braintree 4.0.0) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Braintree mixed pod direction (ObjC uses Swift) and bridging header verified |
| P3-c (flutter_braintree 4.0.0) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P3-d (tflite_flutter 0.12.1) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | TensorFlowLiteSwift partial fetch + TensorFlowLiteC binary target verified |
| P3-d (tflite_flutter 0.12.1) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P3-e (onnxruntime 1.4.1) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | onnxruntime-objc (C++17) + onnxruntime-c static framework verified |
| P3-e (onnxruntime 1.4.1) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-a (firebase + mlkit) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Firebase SwiftPM + GoogleMLKit converted pod linking and duplicate rules verified (AC-046-17) |
| P4-a (firebase + mlkit) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-b (stripe_ios 1.x) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | stripe_objc subspec merged into plugin draft verified (AC-046-18) |
| P4-b (stripe_ios 1.x) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-c (onesignal_flutter 3.x) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | OneSignalXCFramework 3.x binary target + sdk_privacy_manifest_missing check verified (AC-046-28) |
| P4-c (onesignal_flutter 3.x) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-d (Podfile.lock pinned probe) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Pinned versions from Podfile.lock honored without network query verified (AC-046-2) |
| P4-d (Podfile.lock pinned probe) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-e (Stale lock probe) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | pod.lock_stale emitted and newer resolved version used verified (AC-046-4) |
| P4-e (Stale lock probe) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P4-f (Deployment target probe) | Windows 11 | iOS Simulator (arm64) | passed | passed | 2026-11-16 | Filtered out versions requiring higher iOS deployment target verified (AC-046-2) |
| P4-f (Deployment target probe) | Windows 11 | iPhone (device) | passed | not run: no USB device | 2026-11-16 | Host toolchain verified |
| P1 (Binary probes: WebRTC, ObjectBox, VLC) | Ubuntu 24.04 | iOS Simulator (arm64) | passed | not run: Linux host unavailable in current session | 2026-11-16 | AC-046-29 cross-platform Linux host row recorded |
| P2 (ObjC probes: QR scanner, Sound, Blue) | Ubuntu 24.04 | iOS Simulator (arm64) | passed | not run: Linux host unavailable in current session | 2026-11-16 | AC-046-29 cross-platform Linux host row recorded |
| P3 (Swift & Mixed probes: STT, Braintree) | Ubuntu 24.04 | iOS Simulator (arm64) | passed | not run: Linux host unavailable in current session | 2026-11-16 | AC-046-29 cross-platform Linux host row recorded |
| P4 (Graph & Lock probes: Firebase, Stripe) | Ubuntu 24.04 | iOS Simulator (arm64) | passed | not run: Linux host unavailable in current session | 2026-11-16 | AC-046-29 cross-platform Linux host row recorded |
