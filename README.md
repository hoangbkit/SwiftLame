# swift-lame

A Swift package that bundles LAME as an xcframework and provides a Swift wrapper for WAV → MP3 conversion on macOS 15+.

> [!WARNING]
> This package is under active development and is not ready for production use.
> Its API, binary packaging, supported audio formats, and distribution setup may change before a stable release.

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
