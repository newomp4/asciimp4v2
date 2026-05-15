import AVFoundation
import CoreVideo
import CoreGraphics
import AppKit
import Observation

@Observable
final class ExportManager {

    enum Format: String, CaseIterable, Identifiable {
        case h264      = "H.264 MP4"
        case prores422 = "ProRes 422"
        case prores4444 = "ProRes 4444"
        var id: String { rawValue }
        var fileExtension: String { self == .h264 ? "mp4" : "mov" }
        var avFileType: AVFileType { self == .h264 ? .mp4 : .mov }
        var codec: AVVideoCodecType {
            switch self {
            case .h264:      return .h264
            case .prores422: return .proRes422
            case .prores4444: return .proRes4444
            }
        }
    }

    enum OutputSize: String, CaseIterable, Identifiable {
        case source = "Source"
        case hd1080 = "1080p"
        case hd720  = "720p"
        case hd480  = "480p"
        var id: String { rawValue }
        func cgSize(forSource src: CGSize) -> CGSize {
            switch self {
            case .source: return src
            case .hd1080: return CGSize(width: 1920, height: 1080)
            case .hd720:  return CGSize(width: 1280, height: 720)
            case .hd480:  return CGSize(width: 854,  height: 480)
            }
        }
    }

    enum ExportError: LocalizedError {
        case noVideoTrack, readerFailed, writerFailed(Error?)
        var errorDescription: String? {
            switch self {
            case .noVideoTrack:     return "No video track found in source."
            case .readerFailed:     return "Failed to read video frames."
            case .writerFailed(let e): return e?.localizedDescription ?? "Failed to write output file."
            }
        }
    }

    var isExporting = false
    var progress: Double = 0          // 0–1
    var errorMessage: String? = nil

    private var cancelled = false

    func cancel() { cancelled = true }

    // MARK: – Video export

    func exportVideo(
        sourceURL: URL,
        renderer: CPURenderer,
        appState: AppState,
        format: Format,
        outputSizeMode: OutputSize,
        outputFPS: Double,
        outputURL: URL
    ) async {
        await MainActor.run { isExporting = true; progress = 0; errorMessage = nil; cancelled = false }

        do {
            try await _exportVideo(sourceURL: sourceURL, renderer: renderer, appState: appState,
                                   format: format, outputSizeMode: outputSizeMode,
                                   outputFPS: outputFPS, outputURL: outputURL)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isExporting = false }
    }

    private func _exportVideo(
        sourceURL: URL,
        renderer: CPURenderer,
        appState: AppState,
        format: Format,
        outputSizeMode: OutputSize,
        outputFPS: Double,
        outputURL: URL
    ) async throws {

        let asset = AVURLAsset(url: sourceURL)

        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.noVideoTrack
        }

        let sourceDuration = try await asset.load(.duration)
        let sourceFPS      = Double(try await track.load(.nominalFrameRate))
        let naturalSize    = try await track.load(.naturalSize)
        let totalFrames    = max(1, Int(sourceDuration.seconds * sourceFPS))
        let outputSize     = outputSizeMode.cgSize(forSource: naturalSize)

        // Capture viewport size on main thread before going async
        let viewportSize = await MainActor.run { renderer.displayView?.bounds.size ?? .zero }

        // Reader
        let reader = try AVAssetReader(asset: asset)
        let readerSettings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: readerSettings)
        reader.add(readerOutput)

        // Writer
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format.avFileType)

        var videoSettings: [String: Any] = [
            AVVideoCodecKey:  format.codec.rawValue,
            AVVideoWidthKey:  Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        if format == .h264 {
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: Int(outputSize.width * outputSize.height * 4)
            ]
        }

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )
        writer.add(writerInput)

        guard reader.startReading() else { throw ExportError.readerFailed }
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timescale = CMTimeScale(outputFPS * 100)
        let frameDuration = CMTime(value: CMTimeValue(100), timescale: timescale)
        var frameIdx = 0

        let ciCtx   = CIContext(options: [.useSoftwareRenderer: false])
        let tracker = appState.trackerEnabled ? TrackerProcessor() : nil

        while reader.status == .reading, !cancelled {
            guard let sample = readerOutput.copyNextSampleBuffer(),
                  let pixelBuf = CMSampleBufferGetImageBuffer(sample) else { break }

            let ci = CIImage(cvPixelBuffer: pixelBuf)
            guard let cg = ciCtx.createCGImage(ci, from: ci.extent) else {
                frameIdx += 1; continue
            }

            var clusters: [TrackerCluster] = []
            if let tracker {
                clusters = tracker.detectSync(TrackerProcessor.Input(
                    cgImage: cg, mode: appState.detectionMode,
                    maxClusters: appState.maxClusters,
                    sensitivity: appState.sensitivity, minArea: appState.minArea
                ))
            }

            guard let (rendered, _) = Optional(renderer.renderOffline(
                      cg, size: outputSize, for: appState,
                      transparent: true, viewportSize: viewportSize, clusters: clusters)),
                  let rendered,
                  let outBuf = cgImageToPixelBuffer(rendered, width: Int(outputSize.width),
                                                    height: Int(outputSize.height))
            else { frameIdx += 1; continue }

            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(frameIdx))

            while !writerInput.isReadyForMoreMediaData && !cancelled {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard !cancelled else { break }

            adaptor.append(outBuf, withPresentationTime: pts)
            frameIdx += 1

            let p = Double(frameIdx) / Double(totalFrames)
            await MainActor.run { progress = min(p, 1.0) }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error)
        }
        if cancelled {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    // MARK: – Image sequence export

    func exportSequence(
        framePaths: [URL],
        renderer: CPURenderer,
        appState: AppState,
        format: Format,
        outputSizeMode: OutputSize,
        outputFPS: Double,
        outputURL: URL
    ) async {
        await MainActor.run { isExporting = true; progress = 0; errorMessage = nil; cancelled = false }

        do {
            try await _exportSequence(framePaths: framePaths, renderer: renderer, appState: appState,
                                      format: format, outputSizeMode: outputSizeMode,
                                      outputFPS: outputFPS, outputURL: outputURL)
        } catch {
            await MainActor.run { errorMessage = error.localizedDescription }
        }

        await MainActor.run { isExporting = false }
    }

    private func _exportSequence(
        framePaths: [URL],
        renderer: CPURenderer,
        appState: AppState,
        format: Format,
        outputSizeMode: OutputSize,
        outputFPS: Double,
        outputURL: URL
    ) async throws {
        guard !framePaths.isEmpty else { return }

        // Determine output size from first frame
        guard let firstImg = NSImage(contentsOf: framePaths[0]),
              let firstRep = firstImg.representations.first as? NSBitmapImageRep,
              let firstCG  = firstRep.cgImage else { throw ExportError.readerFailed }

        let naturalSize = CGSize(width: firstCG.width, height: firstCG.height)
        let outputSize  = outputSizeMode.cgSize(forSource: naturalSize)

        if FileManager.default.fileExists(atPath: outputURL.path) {
            try FileManager.default.removeItem(at: outputURL)
        }
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: format.avFileType)

        var videoSettings: [String: Any] = [
            AVVideoCodecKey:  format.codec.rawValue,
            AVVideoWidthKey:  Int(outputSize.width),
            AVVideoHeightKey: Int(outputSize.height)
        ]
        if format == .h264 {
            videoSettings[AVVideoCompressionPropertiesKey] = [
                AVVideoAverageBitRateKey: Int(outputSize.width * outputSize.height * 4)
            ]
        }

        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey  as String: Int(outputSize.width),
                kCVPixelBufferHeightKey as String: Int(outputSize.height)
            ]
        )
        writer.add(writerInput)

        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let timescale = CMTimeScale(outputFPS * 100)
        let frameDuration = CMTime(value: 100, timescale: timescale)

        let viewportSize = await MainActor.run { renderer.displayView?.bounds.size ?? .zero }
        let tracker = appState.trackerEnabled ? TrackerProcessor() : nil

        for (idx, path) in framePaths.enumerated() {
            guard !cancelled else { break }

            guard let img = NSImage(contentsOf: path),
                  let rep = img.representations.first as? NSBitmapImageRep,
                  let cg  = rep.cgImage
            else { continue }

            var clusters: [TrackerCluster] = []
            if let tracker {
                clusters = tracker.detectSync(TrackerProcessor.Input(
                    cgImage: cg, mode: appState.detectionMode,
                    maxClusters: appState.maxClusters,
                    sensitivity: appState.sensitivity, minArea: appState.minArea
                ))
            }

            guard let (rendered, _) = Optional(renderer.renderOffline(
                      cg, size: outputSize, for: appState,
                      transparent: true, viewportSize: viewportSize, clusters: clusters)),
                  let rendered,
                  let buf = cgImageToPixelBuffer(rendered, width: Int(outputSize.width),
                                                 height: Int(outputSize.height))
            else { continue }

            let pts = CMTimeMultiply(frameDuration, multiplier: Int32(idx))

            while !writerInput.isReadyForMoreMediaData && !cancelled {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            guard !cancelled else { break }

            adaptor.append(buf, withPresentationTime: pts)

            let p = Double(idx + 1) / Double(framePaths.count)
            await MainActor.run { progress = p }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()

        if writer.status == .failed {
            throw ExportError.writerFailed(writer.error)
        }
        if cancelled {
            try? FileManager.default.removeItem(at: outputURL)
        }
    }

    // MARK: – Helpers

    private func cgImageToPixelBuffer(_ image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        var pb: CVPixelBuffer?
        let attrs: [String: Any] = [
            kCVPixelBufferCGImageCompatibilityKey as String: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey as String: true
        ]
        guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                  kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb) == kCVReturnSuccess,
              let pixelBuffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let ctx = CGContext(
            data:              CVPixelBufferGetBaseAddress(pixelBuffer),
            width:             width,
            height:            height,
            bitsPerComponent:  8,
            bytesPerRow:       CVPixelBufferGetBytesPerRow(pixelBuffer),
            space:             CGColorSpaceCreateDeviceRGB(),
            bitmapInfo:        CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        ) else { return nil }

        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}
