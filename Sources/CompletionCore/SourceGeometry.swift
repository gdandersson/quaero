import Foundation
import CoreGraphics

public enum SourceGeometry {
    /// Vision uses normalized bottom-left bounds; capture frames use global top-left points.
    public static func screenRect(normalized box: CGRect, captureFrame frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + box.minX * frame.width,
               y: frame.minY + (1 - box.maxY) * frame.height,
               width: box.width * frame.width, height: box.height * frame.height)
    }
}
