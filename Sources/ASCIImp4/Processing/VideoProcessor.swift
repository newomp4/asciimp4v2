import AVFoundation
import CoreVideo
import CoreMedia
import QuartzCore

@Observable
final class VideoProcessor {

    var isPlaying:   Bool   = false
    var isLooping:   Bool   = true
    var duration:    Double = 0
    var currentTime: Double = 0
    var hasContent:  Bool   = false
    var fps:         Double = 30

    private var player:       AVPlayer?
    private var playerItem:   AVPlayerItem?
    private var videoOutput:  AVPlayerItemVideoOutput?
    private var displayLink:  CVDisplayLink?
    private var timeObserver: Any?

    var onFrame: ((CVPixelBuffer) -> Void)?

    // ── Load ──────────────────────────────────────────────────────────────────

    func load(url: URL) {
        stop()
        let asset = AVURLAsset(url: url)

        Task { @MainActor in
            do {
                if let track = try await asset.loadTracks(withMediaType: .video).first {
                    self.fps = Double(try await track.load(.nominalFrameRate))
                }
                self.duration = try await asset.load(.duration).seconds
            } catch {
                print("[VideoProcessor] Asset load error:", error)
            }
        }

        let settings: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        let output  = AVPlayerItemVideoOutput(pixelBufferAttributes: settings)
        videoOutput = output

        let item = AVPlayerItem(asset: asset)
        item.add(output)
        playerItem = item

        let p = AVPlayer(playerItem: item)
        p.actionAtItemEnd = .none
        player = p

        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item, queue: .main
        ) { [weak self] _ in
            guard let self, isLooping else { return }
            player?.seek(to: .zero)
            player?.play()
        }

        timeObserver = p.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 15),
            queue: .main
        ) { [weak self] t in
            self?.currentTime = t.seconds
        }

        startDisplayLink()
        hasContent = true
    }

    // ── Playback ──────────────────────────────────────────────────────────────

    func play() {
        player?.play()
        isPlaying = true
    }

    func pause() {
        player?.pause()
        isPlaying = false
    }

    func togglePlayPause() { isPlaying ? pause() : play() }

    // Precise seek — used when scrubbing ends
    func seek(to time: Double) {
        let t = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: t, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    // Fast seek — used while actively scrubbing (loose tolerance for speed)
    func scrub(to time: Double) {
        let t       = CMTime(seconds: time, preferredTimescale: 600)
        let tol     = CMTime(value: 3, timescale: 60)
        player?.seek(to: t, toleranceBefore: tol, toleranceAfter: tol)
    }

    func stop() {
        pause()
        if let obs = timeObserver { player?.removeTimeObserver(obs) }
        timeObserver = nil
        stopDisplayLink()
        player      = nil
        playerItem  = nil
        videoOutput = nil
        hasContent  = false
        currentTime = 0
        duration    = 0
    }

    // ── Display link ──────────────────────────────────────────────────────────

    private func startDisplayLink() {
        var link: CVDisplayLink?
        CVDisplayLinkCreateWithActiveCGDisplays(&link)
        guard let link else { return }

        let ctx = Unmanaged.passUnretained(self).toOpaque()
        CVDisplayLinkSetOutputCallback(link, { _, _, _, _, _, raw -> CVReturn in
            let proc = Unmanaged<VideoProcessor>.fromOpaque(raw!).takeUnretainedValue()
            DispatchQueue.main.async { proc.tick() }
            return kCVReturnSuccess
        }, ctx)

        CVDisplayLinkStart(link)
        displayLink = link
    }

    private func stopDisplayLink() {
        if let dl = displayLink { CVDisplayLinkStop(dl) }
        displayLink = nil
    }

    private func tick() {
        guard
            let output = videoOutput,
            let player = player,
            player.timeControlStatus == .playing
        else { return }

        let hostTime = CACurrentMediaTime()
        let itemTime = output.itemTime(forHostTime: hostTime)
        guard
            output.hasNewPixelBuffer(forItemTime: itemTime),
            let pb = output.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil)
        else { return }

        onFrame?(pb)
    }

    deinit { stop() }
}
