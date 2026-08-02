# BitShift

A focused mobile utility that changes only a video's target bitrate while keeping its resolution, frame rate, audio, metadata, and additional streams as close to the source as the output format permits.

## Features

- Select a video from the device file picker.
- Presets for 512 kbps and every whole Mbps value from 1 through 15.
- Manual input from 1 through 30 Mbps.
- Source-aware H.264, HEVC, VP9, AV1, and MPEG-4 encoding.
- Automatic Android output to `Downloads/BitShift`.
- iOS output exposed in the Files app under the BitShift application folder.
- Direct **Go to Video** action after conversion.
- Red, black, white, and metallic single-screen interface.

## Downloads

Every push to `main` produces downloadable Android and unsigned iOS workflow artifacts. Tags matching `v*` publish a GitHub Release containing:

- `BitShift-Android.apk` — directly installable on Android.
- `BitShift-iOS-unsigned.zip` — an unsigned application bundle for testing or later signing.

iOS does not permit a generally installable IPA without an Apple Developer certificate and provisioning profile. Add signing credentials to the workflow before App Store, TestFlight, or ad-hoc distribution.

## Local development

```shell
flutter pub get
flutter run
```

Android requires API 24 or later. iOS requires iOS 14 or later through the bundled FFmpeg package.

## License

This project uses a GPL-enabled FFmpeg distribution and is licensed under GPL-3.0-or-later.
