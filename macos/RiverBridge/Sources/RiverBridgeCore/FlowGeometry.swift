// Pure geometry for the power-flow scene: a connector between two circles
// starts and ends exactly on their edges, along the line of centers.
// Proved by unit test — the "lines don't touch the circles" defect from the
// owner's screenshot cannot come back silently.

import CoreGraphics

public enum FlowGeometry {
    public struct Circle: Sendable {
        public var center: CGPoint
        public var radius: CGFloat

        public init(center: CGPoint, radius: CGFloat) {
            self.center = center
            self.radius = radius
        }
    }

    /// Point at parameter t (0...1) on a quadratic bezier — the "cable"
    /// between nodes. Pure, so the energy pulse position is testable.
    public static func quadPoint(start: CGPoint, control: CGPoint, end: CGPoint, t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * start.x + 2 * u * t * control.x + t * t * end.x,
            y: u * u * start.y + 2 * u * t * control.y + t * t * end.y
        )
    }

    /// Control point for a cable with `sag` (positive = hangs downward),
    /// placed at the midpoint offset perpendicular-ish (vertical sag).
    public static func cableControl(start: CGPoint, end: CGPoint, sag: CGFloat) -> CGPoint {
        CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + sag)
    }

    /// Endpoints of the connector between two circles, each ON its edge.
    /// Returns nil when the circles overlap (no visible connector).
    public static func connector(from a: Circle, to b: Circle) -> (start: CGPoint, end: CGPoint)? {
        let dx = b.center.x - a.center.x
        let dy = b.center.y - a.center.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > a.radius + b.radius else { return nil }
        let ux = dx / distance
        let uy = dy / distance
        return (
            start: CGPoint(x: a.center.x + ux * a.radius, y: a.center.y + uy * a.radius),
            end: CGPoint(x: b.center.x - ux * b.radius, y: b.center.y - uy * b.radius)
        )
    }
}
