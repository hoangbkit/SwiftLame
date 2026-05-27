# swift-lame

A Swift package that bundles LAME as an xcframework and provides a Swift wrapper for WAV → MP3 conversion on macOS 15+.

> [!WARNING]
> This package is under active development and is not ready for production use.
> Its API, binary packaging, supported audio formats, and distribution setup may change before a stable release.

## Current Limitations

This version is intended for an immediate TTS conversion use case and has
been verified with mono, 24 kHz, 32-bit Float WAV inputs.

- Output preserves the WAV input sample rate and channel count. The verified
  TTS inputs produce mono, 24 kHz MP3 output.
- `Config.sampleRate` is currently not applied; the input WAV sample rate is
  used instead.
- Requesting `320` kbps for the verified 24 kHz mono inputs produces 160 kbps
  MP3 output due to the encoding profile supported for that input.
- PCM16, stereo WAV input, malformed/unsupported input handling, and
  `convert(wavBuffer:)` need additional validation before broader use.

## Setup

Build the xcframework once before using the package:

```bash
chmod +x build_lame.sh
./build_lame.sh
```

This produces `Frameworks/lame.xcframework`.

## Usage

```swift
import SwiftLame

let converter = AudioConverter(config: .init(bitrate: 320))

for try await progress in converter.convert(from: wavURL, to: mp3URL) {
    print("\(Int(progress * 100))%")
}
// stream finishes = done
```

## Config

| Property     | Default | Description                      |
|--------------|---------|----------------------------------|
| `sampleRate` | 44100   | Input sample rate (Hz)           |
| `bitrate`    | 192     | Output bitrate (kbps)            |
| `quality`    | 2       | Encoder quality (0=best, 9=worst)|

## Publishing to GitHub

```bash
zip -r lame.xcframework.zip Frameworks/lame.xcframework
swift package compute-checksum lame.xcframework.zip
```

Then switch `Package.swift` to `.binaryTarget(name:url:checksum:)`.
