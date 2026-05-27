import Foundation
import lame

public actor AudioConverter {
    
    public struct Config: Sendable {
        public var sampleRate: Int32
        public var bitrate: Int32
        public var quality: Int32
        
        public init(
            sampleRate: Int32 = 44100,
            bitrate: Int32 = 192,
            quality: Int32 = 2
        ) {
            self.sampleRate = sampleRate
            self.bitrate = bitrate
            self.quality = quality
        }
        
        public static let `default` = Config()
    }
    
    private let config: Config
    
    public init(config: Config = .default) {
        self.config = config
    }
    
    /// Convert a WAV file to MP3, streaming progress as 0.0–1.0.
    /// Stream finishes when conversion is complete.
    public func convert(
        from inputURL: URL,
        to outputURL: URL
    ) -> AsyncThrowingStream<Float, Error> {
        let config = self.config
        return AsyncThrowingStream { continuation in
            Task.detached(priority: .userInitiated) {
                do {
                    try AudioConverter.encodeSync(
                        from: inputURL,
                        to: outputURL,
                        config: config,
                        onProgress: { continuation.yield($0) }
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
    
    /// Convert an in-memory WAV buffer to an MP3 buffer.
    public func convert(wavBuffer: Data) async throws -> Data {
        let config = self.config
        return try await Task.detached(priority: .userInitiated) {
            try AudioConverter.encodeWAVBufferSync(wavBuffer, config: config)
        }.value
    }
    
    // MARK: - Private
    
    private struct WAVInfo {
        enum SampleFormat {
            case pcm16
            case ieeeFloat32
        }
        
        let sampleRate: Int32
        let channelCount: Int32
        let bitsPerSample: Int
        let sampleFormat: SampleFormat
        let dataRange: Range<Int>
        
        var bytesPerFrame: Int {
            Int(channelCount) * (bitsPerSample / 8)
        }
        
        var frameCount: Int {
            dataRange.count / bytesPerFrame
        }
    }
    
    private static func encodeSync(
        from inputURL: URL,
        to outputURL: URL,
        config: Config,
        onProgress: @Sendable (Float) -> Void
    ) throws {
        let wavData: Data
        do {
            wavData = try Data(contentsOf: inputURL, options: .mappedIfSafe)
        } catch {
            throw LameError.cannotOpenInput(inputURL)
        }
        
        let mp3Data = try encodeWAVBufferSync(wavData, config: config, onProgress: onProgress)
        
        do {
            try mp3Data.write(to: outputURL, options: .atomic)
        } catch {
            throw LameError.cannotOpenOutput(outputURL)
        }
    }
    
    private static func encodeWAVBufferSync(
        _ wavBuffer: Data,
        config: Config,
        onProgress: @Sendable (Float) -> Void = { _ in }
    ) throws -> Data {
        let wavInfo = try parseWAV(wavBuffer)
        
        guard let lame = lame_init() else {
            throw LameError.initFailed
        }
        defer { lame_close(lame) }
        
        try configureEncoder(
            lame,
            bitrate: config.bitrate,
            quality: config.quality,
            sampleRate: wavInfo.sampleRate,
            channelCount: wavInfo.channelCount
        )
        
        let pcmChunkFrames = 8192
        let mp3BufferSize = Int32(Int(Double(pcmChunkFrames) * 1.25) + 7200)
        let mp3Buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: Int(mp3BufferSize))
        defer { mp3Buffer.deallocate() }
        
        var mp3Data = Data()
        mp3Data.reserveCapacity(Int(Double(wavInfo.dataRange.count) * 1.25) + 7200)
        
        switch wavInfo.sampleFormat {
        case .pcm16:
            try encodePCM16(
                wavBuffer,
                wavInfo: wavInfo,
                lame: lame,
                mp3Buffer: mp3Buffer,
                mp3BufferSize: mp3BufferSize,
                pcmChunkFrames: pcmChunkFrames,
                mp3Data: &mp3Data,
                onProgress: onProgress
            )
        case .ieeeFloat32:
            try encodeFloat32(
                wavBuffer,
                wavInfo: wavInfo,
                lame: lame,
                mp3Buffer: mp3Buffer,
                mp3BufferSize: mp3BufferSize,
                pcmChunkFrames: pcmChunkFrames,
                mp3Data: &mp3Data,
                onProgress: onProgress
            )
        }
        
        let flushWrite = lame_encode_flush(lame, mp3Buffer, mp3BufferSize)
        try appendEncodedBytes(flushWrite, from: mp3Buffer, to: &mp3Data)
        onProgress(1)
        
        return mp3Data
    }
    
    private static func encodePCM16(
        _ wavBuffer: Data,
        wavInfo: WAVInfo,
        lame: OpaquePointer,
        mp3Buffer: UnsafeMutablePointer<UInt8>,
        mp3BufferSize: Int32,
        pcmChunkFrames: Int,
        mp3Data: inout Data,
        onProgress: @Sendable (Float) -> Void
    ) throws {
        try wavBuffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw LameError.invalidWAVFile
            }
            
            let sampleBase = baseAddress
                .advanced(by: wavInfo.dataRange.lowerBound)
                .assumingMemoryBound(to: Int16.self)
            let totalFrames = max(wavInfo.frameCount, 1)
            
            var processedFrames = 0
            while processedFrames < wavInfo.frameCount {
                let chunkFrames = min(pcmChunkFrames, wavInfo.frameCount - processedFrames)
                let chunkPointer = sampleBase.advanced(by: processedFrames * Int(wavInfo.channelCount))
                let write: Int32
                
                if wavInfo.channelCount == 1 {
                    write = lame_encode_buffer(
                        lame,
                        chunkPointer,
                        nil,
                        Int32(chunkFrames),
                        mp3Buffer,
                        mp3BufferSize
                    )
                } else {
                    write = lame_encode_buffer_interleaved(
                        lame,
                        UnsafeMutablePointer(mutating: chunkPointer),
                        Int32(chunkFrames),
                        mp3Buffer,
                        mp3BufferSize
                    )
                }
                
                try appendEncodedBytes(write, from: mp3Buffer, to: &mp3Data)
                processedFrames += chunkFrames
                onProgress(min(Float(processedFrames) / Float(totalFrames), 1))
            }
        }
    }
    
    private static func encodeFloat32(
        _ wavBuffer: Data,
        wavInfo: WAVInfo,
        lame: OpaquePointer,
        mp3Buffer: UnsafeMutablePointer<UInt8>,
        mp3BufferSize: Int32,
        pcmChunkFrames: Int,
        mp3Data: inout Data,
        onProgress: @Sendable (Float) -> Void
    ) throws {
        try wavBuffer.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                throw LameError.invalidWAVFile
            }
            
            let sampleBase = baseAddress
                .advanced(by: wavInfo.dataRange.lowerBound)
                .assumingMemoryBound(to: Float.self)
            let totalFrames = max(wavInfo.frameCount, 1)
            
            var processedFrames = 0
            while processedFrames < wavInfo.frameCount {
                let chunkFrames = min(pcmChunkFrames, wavInfo.frameCount - processedFrames)
                let chunkPointer = sampleBase.advanced(by: processedFrames * Int(wavInfo.channelCount))
                let write: Int32
                
                if wavInfo.channelCount == 1 {
                    write = lame_encode_buffer_ieee_float(
                        lame,
                        chunkPointer,
                        nil,
                        Int32(chunkFrames),
                        mp3Buffer,
                        mp3BufferSize
                    )
                } else {
                    write = lame_encode_buffer_interleaved_ieee_float(
                        lame,
                        chunkPointer,
                        Int32(chunkFrames),
                        mp3Buffer,
                        mp3BufferSize
                    )
                }
                
                try appendEncodedBytes(write, from: mp3Buffer, to: &mp3Data)
                processedFrames += chunkFrames
                onProgress(min(Float(processedFrames) / Float(totalFrames), 1))
            }
        }
    }
    
    private static func configureEncoder(
        _ lame: OpaquePointer,
        bitrate: Int32,
        quality: Int32,
        sampleRate: Int32,
        channelCount: Int32
    ) throws {
        lame_set_in_samplerate(lame, sampleRate)
        lame_set_num_channels(lame, channelCount)
        lame_set_brate(lame, bitrate)
        lame_set_quality(lame, quality)
        lame_set_VBR(lame, vbr_off)
        
        if channelCount == 1 {
            lame_set_mode(lame, MONO)
        } else {
            lame_set_mode(lame, STEREO)
        }
        
        guard lame_init_params(lame) >= 0 else {
            throw LameError.paramsFailed
        }
    }
    
    private static func appendEncodedBytes(
        _ byteCount: Int32,
        from buffer: UnsafeMutablePointer<UInt8>,
        to data: inout Data
    ) throws {
        if byteCount < 0 {
            throw LameError.encodingFailed(byteCount)
        }
        
        if byteCount > 0 {
            data.append(buffer, count: Int(byteCount))
        }
    }
    
    private static func parseWAV(_ data: Data) throws -> WAVInfo {
        guard data.count >= 12 else {
            throw LameError.invalidWAVFile
        }
        
        guard chunkID(in: data, at: 0) == "RIFF", chunkID(in: data, at: 8) == "WAVE" else {
            throw LameError.invalidWAVFile
        }
        
        var formatTag: UInt16?
        var channelCount: UInt16?
        var sampleRate: UInt32?
        var bitsPerSample: UInt16?
        var dataRange: Range<Int>?
        var offset = 12
        
        while offset + 8 <= data.count {
            let id = chunkID(in: data, at: offset)
            let chunkSize = try Int(readUInt32LE(in: data, at: offset + 4))
            let chunkStart = offset + 8
            let chunkEnd = chunkStart + chunkSize
            
            guard chunkEnd <= data.count else {
                throw LameError.invalidWAVFile
            }
            
            switch id {
            case "fmt ":
                guard chunkSize >= 16 else {
                    throw LameError.invalidWAVFile
                }
                formatTag = try readUInt16LE(in: data, at: chunkStart)
                channelCount = try readUInt16LE(in: data, at: chunkStart + 2)
                sampleRate = try readUInt32LE(in: data, at: chunkStart + 4)
                bitsPerSample = try readUInt16LE(in: data, at: chunkStart + 14)
            case "data":
                dataRange = chunkStart..<chunkEnd
            default:
                break
            }
            
            offset = chunkEnd + (chunkSize % 2)
        }
        
        guard
            let resolvedFormatTag = formatTag,
            let resolvedChannelCount = channelCount,
            let resolvedSampleRate = sampleRate,
            let resolvedBitsPerSample = bitsPerSample,
            let resolvedDataRange = dataRange
        else {
            throw LameError.invalidWAVFile
        }
        
        guard resolvedChannelCount == 1 || resolvedChannelCount == 2 else {
            throw LameError.unsupportedWAVFormat(
                "Only mono and stereo WAV files are supported"
            )
        }
        
        let sampleFormat: WAVInfo.SampleFormat
        switch (resolvedFormatTag, resolvedBitsPerSample) {
        case (1, 16):
            sampleFormat = .pcm16
        case (3, 32):
            sampleFormat = .ieeeFloat32
        default:
            throw LameError.unsupportedWAVFormat(
                "Only 16-bit PCM and 32-bit IEEE float WAV files are supported"
            )
        }
        
        let wavInfo = WAVInfo(
            sampleRate: Int32(resolvedSampleRate),
            channelCount: Int32(resolvedChannelCount),
            bitsPerSample: Int(resolvedBitsPerSample),
            sampleFormat: sampleFormat,
            dataRange: resolvedDataRange
        )
        
        guard wavInfo.bytesPerFrame > 0, resolvedDataRange.count.isMultiple(of: wavInfo.bytesPerFrame) else {
            throw LameError.invalidWAVFile
        }
        
        return wavInfo
    }
    
    private static func chunkID(in data: Data, at offset: Int) -> String {
        guard offset + 4 <= data.count else { return "" }
        return String(decoding: data[offset..<(offset + 4)], as: UTF8.self)
    }
    
    private static func readUInt16LE(in data: Data, at offset: Int) throws -> UInt16 {
        guard offset + 2 <= data.count else {
            throw LameError.invalidWAVFile
        }
        
        return data[offset..<(offset + 2)].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt16.self).littleEndian
        }
    }
    
    private static func readUInt32LE(in data: Data, at offset: Int) throws -> UInt32 {
        guard offset + 4 <= data.count else {
            throw LameError.invalidWAVFile
        }
        
        return data[offset..<(offset + 4)].withUnsafeBytes { rawBuffer in
            rawBuffer.load(as: UInt32.self).littleEndian
        }
    }
}

// MARK: - Errors

public enum LameError: Error, LocalizedError {
    case cannotOpenInput(URL)
    case cannotOpenOutput(URL)
    case initFailed
    case paramsFailed
    case encodingFailed(Int32)
    case invalidWAVFile
    case unsupportedWAVFormat(String)
    
    public var errorDescription: String? {
        switch self {
            case .cannotOpenInput(let url):  return "Cannot open input: \(url.lastPathComponent)"
            case .cannotOpenOutput(let url): return "Cannot open output: \(url.lastPathComponent)"
            case .initFailed:                return "LAME encoder failed to initialize"
            case .paramsFailed:              return "LAME encoder parameters are invalid"
            case .encodingFailed(let code):  return "LAME encoding failed with status \(code)"
            case .invalidWAVFile:            return "WAV file is invalid or missing required chunks"
            case .unsupportedWAVFormat(let details):
                return details
        }
    }
}
