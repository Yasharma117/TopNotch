import Testing
import CoreGraphics
import SwiftUI
@testable import TopNotch

/// The notch silhouette is the app's signature shape, and it went a long time
/// looking lopsided because nothing checked it. These sample the rendered path
/// rather than the control points, so a wrong curve cannot slip through.
struct NotchBoxShapeTests {

    private static let resizeRange: [CGFloat] = [320, 384, 420, 512, 560, 680]

    private func path(width: CGFloat, height: CGFloat = 200) -> CGPath {
        NotchBoxShape(bottomRadius: NotchChromeMetrics.bottomRadius)
            .path(in: CGRect(x: 0, y: 0, width: width, height: height))
            .cgPath
    }

    /// Widest gap between an edge and where its mirror image should be.
    private func asymmetry(width: CGFloat) -> CGFloat {
        let p = path(width: width)
        var worst: CGFloat = 0
        for step in 0...88 {
            let y = CGFloat(step) * 0.5
            guard let left = firstFilledX(p, y: y, from: 0, to: width, by: 0.25),
                  let right = firstFilledX(p, y: y, from: width, to: 0, by: -0.25)
            else { continue }
            worst = max(worst, abs(left - (width - right)))
        }
        return worst
    }

    private func firstFilledX(_ p: CGPath, y: CGFloat, from: CGFloat, to: CGFloat, by: CGFloat) -> CGFloat? {
        var x = from
        while by > 0 ? x <= to : x >= to {
            if p.contains(CGPoint(x: x, y: y)) { return x }
            x += by
        }
        return nil
    }

    @Test("the notch is symmetric at every width the resize handle allows")
    func symmetric() {
        for width in Self.resizeRange {
            #expect(asymmetry(width: width) < 1.0,
                    "notch is \(asymmetry(width: width))pt lopsided at \(width)pt wide")
        }
    }

    @Test("the shape never escapes the panel it is drawn into")
    func staysInBounds() {
        for width in Self.resizeRange {
            let box = path(width: width).boundingBox
            #expect(box.minX >= -0.01)
            #expect(box.minY >= -0.01)
            #expect(box.maxX <= width + 0.01)
            #expect(box.maxY <= 200.01)
        }
    }

    @Test("a collapsed panel is the bare notch, with no shoulders")
    func collapsedHasNoShoulders() {
        // blend is 0 at or below notchWidth + 4, so the shape is a plain rounded rect.
        let collapsed = path(width: NotchChromeMetrics.notchWidth + 4, height: 44)
        #expect(!collapsed.isEmpty)
        #expect(collapsed.boundingBox.width <= NotchChromeMetrics.notchWidth + 4.01)
    }

    @Test("the shape stays centred on the panel midline")
    func staysCentred() {
        for width in Self.resizeRange {
            let p = path(width: width)
            for step in 1...34 {
                let y = CGFloat(step) * 0.5   // through the tab and the shoulder band
                guard let left = firstFilledX(p, y: y, from: 0, to: width, by: 0.1),
                      let right = firstFilledX(p, y: y, from: width, to: 0, by: -0.1)
                else { continue }
                #expect(abs((left + right) / 2 - width / 2) < 0.2,
                        "off-centre by \((left + right) / 2 - width / 2)pt at y=\(y), width=\(width)")
            }
        }
    }

    @Test("the shoulders flare outward from the tab, never inward")
    func shouldersFlareOutward() {
        // Emergence should widen the silhouette monotonically from the tab down to
        // the shelf. A control point on the wrong side would pinch it instead.
        for width in Self.resizeRange {
            let p = path(width: width)
            var previous: CGFloat = 0
            for step in 1...34 {
                let y = CGFloat(step) * 0.5
                guard let left = firstFilledX(p, y: y, from: 0, to: width, by: 0.1),
                      let right = firstFilledX(p, y: y, from: width, to: 0, by: -0.1)
                else { continue }
                let span = right - left
                #expect(span >= previous - 0.2, "silhouette narrows at y=\(y), width=\(width)")
                previous = span
            }
            #expect(previous > NotchChromeMetrics.notchWidth,
                    "shoulders never widened past the tab at width \(width)")
        }
    }
}
