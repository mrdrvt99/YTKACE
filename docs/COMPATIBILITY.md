# Compatibility

## Supplied baseline

YouTube 21.26.4 has a minimum deployment version of iOS 16.0 and links
AppIntents. This baseline is therefore supported on iOS 16 and newer. Changing
Info.plist alone cannot make it an iOS 15 application.

The YTKACE dylib itself targets iOS 15 and can be repacked into an older
YouTube baseline that also targets iOS 15.

## Architectures

YTKACE builds arm64 and arm64e into one universal dylib. The supplied YouTube
executable is arm64 and selects the arm64 slice on all supported devices.

Linux Theos toolchains can emit an arm64e slice but older Linux linkers may
warn about the arm64e ABI. Release artifacts must build and verify that slice
with a current macOS/Xcode toolchain.

## YouTube updates

YouTube's internal classes are private and can change without notice. Hooks
resolve classes and selectors at runtime and fail closed. A missing class
disables one feature instead of terminating the app.

## Install paths

The same repacked IPA can be installed through TrollStore, AppSync-compatible
installers, or re-signed by a developer-certificate sideloader. No runtime
injection environment is required.
