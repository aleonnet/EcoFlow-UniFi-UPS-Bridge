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
