import CoreGraphics
import Accelerate
import AppKit

final class TrackerProcessor {

    private let queue = DispatchQueue(label: "com.asciimp4.tracker", qos: .utility)
    // isDetecting is read + written only on the main thread (detectAsync + completion)
    private var isDetecting = false
    private var prevLuma: [Float]? = nil
    private var prevW = 0, prevH = 0

    struct Input {
        let cgImage: CGImage
        let mode: DetectionMode
        let maxClusters: Int
        let sensitivity: Float
        let minArea: Float
    }

    // Async entry point — drops the frame if a detection is already in flight.
    // Called on main thread; completion always fires on main thread.
    func detectSync(_ input: Input) -> [TrackerCluster] {
        detect(input)
    }

    func detectAsync(_ input: Input, completion: @escaping ([TrackerCluster]) -> Void) {
        guard !isDetecting else { return }
        isDetecting = true
        queue.async {
            let result = self.detect(input)
            DispatchQueue.main.async {
                self.isDetecting = false
                completion(result)
            }
        }
    }

    // ── Core detect (must only be called from self.queue) ─────────────────────

    private func detect(_ input: Input) -> [TrackerCluster] {
        guard let (luma, w, h) = extractLuma(from: input.cgImage) else { return [] }

        let n = w * h

        // Random mode: skip k-means, place boxes on valid (non-transparent) pixels
        if input.mode == .random {
            return randomClusters(luma: luma, w: w, h: h, input: input)
        }

        var score = [Float](repeating: 0, count: n)
        switch input.mode {
        case .bright: score = luma
        case .dark:   score = luma.map { 1.0 - $0 }
        case .edge:   score = sobelEdge(luma: luma, width: w, height: h)
        case .motion:
            if let prev = prevLuma, prev.count == n {
                for i in 0..<n { score[i] = abs(luma[i] - prev[i]) }
            } else {
                score = luma
            }
        case .random: break
        }
        prevLuma = luma
        prevW = w; prevH = h

        let thresh = 0.2 + input.sensitivity * 0.6
        var hot = [(x: Int, y: Int)]()
        for i in 0..<n where score[i] >= thresh {
            hot.append((i % w, i / w))
        }
        guard !hot.isEmpty else { return [] }

        // Subsample large point sets before k-means for performance
        var sample = hot
        if sample.count > 800 {
            let stride = sample.count / 800
            sample = (0..<800).map { sample[min($0 * stride, sample.count - 1)] }
        }

        let k = min(input.maxClusters, sample.count)
        let centers = kmeans(points: sample, k: k, iterations: 2)

        var boxes = [Int: (minX: Int, minY: Int, maxX: Int, maxY: Int, count: Int)]()
        for pt in hot {
            let ci = nearestCenter(pt, centers: centers)
            var b  = boxes[ci] ?? (pt.x, pt.y, pt.x, pt.y, 0)
            b.minX = min(b.minX, pt.x); b.minY = min(b.minY, pt.y)
            b.maxX = max(b.maxX, pt.x); b.maxY = max(b.maxY, pt.y)
            b.count += 1
            boxes[ci] = b
        }

        let fw = CGFloat(w), fh = CGFloat(h)
        var result = [TrackerCluster]()
        for (i, (_, b)) in boxes.sorted(by: { $0.key < $1.key }).enumerated() {
            let area = CGFloat(b.count)
            guard area >= CGFloat(input.minArea) else { continue }
            let rect = CGRect(
                x:      CGFloat(b.minX) / fw,
                y:      CGFloat(b.minY) / fh,
                width:  CGFloat(b.maxX - b.minX + 1) / fw,
                height: CGFloat(b.maxY - b.minY + 1) / fh
            )
            let ctr  = CGPoint(x: CGFloat(centers[i % centers.count].x) / fw,
                               y: CGFloat(centers[i % centers.count].y) / fh)
            let conf = Float(b.count) / Float(hot.count)
            result.append(TrackerCluster(id: i, center: ctr, bounds: rect,
                                         area: area, confidence: conf))
        }
        return result.sorted { $0.area > $1.area }
    }

    private func randomClusters(luma: [Float], w: Int, h: Int, input: Input) -> [TrackerCluster] {
        let n = w * h
        let fw = CGFloat(w), fh = CGFloat(h)

        // Build list of valid pixel positions (non-transparent / visible)
        var valid = [(x: Int, y: Int)]()
        valid.reserveCapacity(n / 4)
        for i in 0..<n where luma[i] > 0.05 {
            valid.append((i % w, i / w))
        }
        if valid.isEmpty {
            // Fall back to full-frame random placement
            for i in 0..<n { valid.append((i % w, i / w)) }
        }

        let k = input.maxClusters
        let sizeScale = CGFloat(0.05 + input.sensitivity * 0.35)
        var result = [TrackerCluster]()

        for i in 0..<k {
            guard let anchor = valid.randomElement() else { continue }
            let cx = CGFloat(anchor.x) / fw
            let cy = CGFloat(anchor.y) / fh
            let bw = sizeScale * CGFloat.random(in: 0.5...1.5)
            let bh = bw * CGFloat.random(in: 0.5...1.2)
            let ox = max(0, cx - bw / 2)
            let oy = max(0, cy - bh / 2)
            let bounds = CGRect(x: ox, y: oy,
                                width: min(bw, 1.0 - ox),
                                height: min(bh, 1.0 - oy))
            result.append(TrackerCluster(id: i,
                                         center: CGPoint(x: cx, y: cy),
                                         bounds: bounds,
                                         area: 500,
                                         confidence: 1.0))
        }
        return result
    }

    // ── Luma extraction ───────────────────────────────────────────────────────

    private func extractLuma(from image: CGImage) -> (luma: [Float], width: Int, height: Int)? {
        let maxDim = 256
        let scale  = min(1.0, Double(maxDim) / Double(max(image.width, image.height)))
        let sw     = max(1, Int(Double(image.width)  * scale))
        let sh     = max(1, Int(Double(image.height) * scale))

        guard let ctx = CGContext(
            data: nil, width: sw, height: sh,
            bitsPerComponent: 8, bytesPerRow: sw * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        ctx.draw(image, in: CGRect(x: 0, y: 0, width: sw, height: sh))
        guard let bytes = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

        let n = sw * sh
        var luma = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let r = Float(bytes[i*4])   / 255.0
            let g = Float(bytes[i*4+1]) / 255.0
            let b = Float(bytes[i*4+2]) / 255.0
            luma[i] = 0.299*r + 0.587*g + 0.114*b
        }
        return (luma, sw, sh)
    }

    // ── Sobel edge ────────────────────────────────────────────────────────────

    private func sobelEdge(luma: [Float], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: luma.count)
        for y in 1..<(height-1) {
            for x in 1..<(width-1) {
                let tl = luma[(y-1)*width+(x-1)]; let tc = luma[(y-1)*width+x]; let tr = luma[(y-1)*width+(x+1)]
                let ml = luma[y*width+(x-1)];                                    let mr = luma[y*width+(x+1)]
                let bl = luma[(y+1)*width+(x-1)]; let bc = luma[(y+1)*width+x]; let br = luma[(y+1)*width+(x+1)]
                let gx = -tl - 2*ml - bl + tr + 2*mr + br
                let gy = -tl - 2*tc - tr + bl + 2*bc + br
                out[y*width+x] = min(sqrt(gx*gx + gy*gy), 1.0)
            }
        }
        return out
    }

    // ── K-means ───────────────────────────────────────────────────────────────

    private func kmeans(points: [(x: Int, y: Int)], k: Int, iterations: Int) -> [(x: Int, y: Int)] {
        guard k > 0, !points.isEmpty else { return [] }
        // Random initialization so clusters shift between detection passes (no sticky lock-on)
        var centers = (0..<k).map { _ in points[Int.random(in: 0..<points.count)] }
        var assign  = [Int](repeating: 0, count: points.count)

        for _ in 0..<iterations {
            for (i, pt) in points.enumerated() { assign[i] = nearestCenter(pt, centers: centers) }
            var sx = [Int](repeating: 0, count: k)
            var sy = [Int](repeating: 0, count: k)
            var cnt = [Int](repeating: 0, count: k)
            for (i, pt) in points.enumerated() {
                let ci = assign[i]; sx[ci] += pt.x; sy[ci] += pt.y; cnt[ci] += 1
            }
            for c in 0..<k where cnt[c] > 0 {
                centers[c] = (sx[c] / cnt[c], sy[c] / cnt[c])
            }
        }
        return centers
    }

    private func nearestCenter(_ pt: (x: Int, y: Int), centers: [(x: Int, y: Int)]) -> Int {
        var best = 0, bestD = Int.max
        for (i, c) in centers.enumerated() {
            let d = (pt.x - c.x) * (pt.x - c.x) + (pt.y - c.y) * (pt.y - c.y)
            if d < bestD { bestD = d; best = i }
        }
        return best
    }
}
