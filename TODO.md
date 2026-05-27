# Release Readiness TODO

SwiftLame is usable for current happy-path testing, but it is not ready for a
stable public release or production dependency.

## High Priority

- Add conversion coverage for mono PCM16 WAV input.
- Add conversion coverage for stereo PCM16 WAV input.
- Add conversion coverage for stereo Float32 WAV input.
- Add tests for the public in-memory `convert(wavBuffer:)` API.
- Fix or remove `Config.sampleRate`: it is public, but conversion currently
  uses the sample rate parsed from the WAV input instead.
- Replace the current custom bitrate assertion with a meaningful test using a
  44.1 kHz or 48 kHz stereo fixture and verify output bitrate metadata. The
  current 24 kHz mono fixture produces 160 kbps output even when requesting
  320 kbps.

## Error Handling

- Test invalid or truncated WAV data returns `LameError.invalidWAVFile`.
- Test unsupported PCM formats, such as 24-bit input, return
  `LameError.unsupportedWAVFormat`.
- Test WAV files with more than two channels are rejected.
- Test a missing input file returns `LameError.cannotOpenInput`.
- Test an unwritable output destination returns `LameError.cannotOpenOutput`.

## Progress And Output

- Assert conversion progress finishes at exactly `1.0`.
- Assert non-empty supported input emits at least one progress value.
- Validate produced MP3 metadata for representative inputs, including channel
  count, sample rate, and bitrate where the configured bitrate is supported.

## Distribution And Release

- Include LAME's complete upstream LGPL license text with the distributed
  binary artifact.
- Confirm that distributing the statically linked `libmp3lame` XCFramework
  satisfies LGPL source and relinking obligations.
- Add a verified upstream source checksum to `build_lame.sh`.
- Decide whether the release should embed `Frameworks/lame.xcframework` in
  the repository or distribute it as a checksum-pinned release artifact.
- Keep `master` release-ready and publish tested snapshots as `0.x` tags.

## Current Coverage Snapshot

Coverage from `swift test --enable-code-coverage` on May 27, 2026:

- `AudioConverter.swift`: approximately 68% line coverage.
- Covered input profile: mono, 24 kHz, Float32 WAV.
- Not covered: PCM16 encoding, stereo encoding, in-memory conversion, and
  public error paths.
