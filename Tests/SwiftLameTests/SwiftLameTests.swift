import Foundation
import Testing
@testable import SwiftLame

@Suite(.serialized)
struct SwiftLameTests {

    // MARK: - Paths

    private let outputFolder = runOutputFolder()

    private func inputAudioFiles() throws -> [URL] {
        let inputAudiosFolder = try #require(Bundle.module.url(
            forResource: "InputAudios",
            withExtension: nil
        ), "Bundled InputAudios fixture directory was not found")

        let urls = try FileManager.default.contentsOfDirectory(
            at: inputAudiosFolder,
            includingPropertiesForKeys: nil
        )
            .filter { $0.pathExtension.lowercased() == "wav" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        try #require(!urls.isEmpty, "No WAV fixtures found in bundled InputAudios directory")
        return urls
    }

    // MARK: - Tests

    @Test
    func conversionProducesFileForAllInputAudios() async throws {
        for input in try inputAudioFiles() {
            let output = outputFolder
                .appendingPathComponent(input.lastPathComponent)
                .deletingPathExtension()
                .appendingPathExtension("mp3")

            try await convertAndAssertOutput(input: input, output: output)
        }
    }

    @Test
    func progressIsMonotonicallyIncreasing() async throws {
        let input = try inputAudioFiles()[0]
        let output = outputFolder.appendingPathComponent("progress.mp3")

        try? FileManager.default.removeItem(at: output)

        let converter = AudioConverter()
        var last: Float = 0

        for try await progress in await converter.convert(from: input, to: output) {
            #expect(progress >= last, "Progress went backwards: \(progress) < \(last)")
            last = progress
        }

        #expect(last > 0, "No progress was reported")
    }

    @Test
    func customConfig() async throws {
        let input = try inputAudioFiles()[0]
        let output = outputFolder.appendingPathComponent("custom-320.mp3")

        try? FileManager.default.removeItem(at: output)

        let config = AudioConverter.Config(sampleRate: 44100, bitrate: 320, quality: 0)
        let converter = AudioConverter(config: config)

        for try await _ in await converter.convert(from: input, to: output) {}

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let fileSize = attributes[.size] as? Int ?? 0
        #expect(fileSize > 0, "320kbps MP3 file is empty")

        print("320kbps output: \(output.path) (\(fileSize) bytes)")
    }

    private func convertAndAssertOutput(input: URL, output: URL) async throws {
        try? FileManager.default.removeItem(at: output)

        let converter = AudioConverter()
        for try await _ in await converter.convert(from: input, to: output) {}

        #expect(
            FileManager.default.fileExists(atPath: output.path),
            "MP3 file was not created at \(output.path)"
        )

        let attributes = try FileManager.default.attributesOfItem(atPath: output.path)
        let fileSize = attributes[.size] as? Int ?? 0
        #expect(fileSize > 0, "MP3 file is empty")

        print("Output: \(output.path)")
        print("Size: \(fileSize) bytes")
    }
}

private func repoRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func runOutputFolder() -> URL {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd-HH-mm-ss"

    let output = repoRoot()
        .appendingPathComponent("tmp", isDirectory: true)
        .appendingPathComponent("swiftlame-tests-output-\(formatter.string(from: Date()))", isDirectory: true)
    try? FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    return output
}
