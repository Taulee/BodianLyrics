import CoreGraphics

public enum OverlayPlacement {
    public static func screenIndex(ofWindowBounds windowBounds: CGRect, screens: [CGRect]) -> Int? {
        guard let primary = screens.first else { return nil }
        let flipped = CGRect(x: windowBounds.minX, y: primary.maxY - windowBounds.maxY,
                             width: windowBounds.width, height: windowBounds.height)
        var best: (index: Int, area: CGFloat)?
        for (index, screen) in screens.enumerated() {
            let overlap = screen.intersection(flipped)
            guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
            let area = overlap.width * overlap.height
            if area > (best?.area ?? 0) { best = (index, area) }
        }
        return best?.index
    }
}
