// Fence: connectors are born and die ON the circle edges, by construction.

import CoreGraphics
import Testing
@testable import RiverBridgeCore

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = a.x - b.x, dy = a.y - b.y
    return (dx * dx + dy * dy).squareRoot()
}

@Test func connectorTouchesBothEdges() throws {
    let a = FlowGeometry.Circle(center: .init(x: 60, y: 150), radius: 40)
    let b = FlowGeometry.Circle(center: .init(x: 400, y: 150), radius: 110)
    let conn = try #require(FlowGeometry.connector(from: a, to: b))
    #expect(abs(distance(conn.start, a.center) - a.radius) < 0.001)
    #expect(abs(distance(conn.end, b.center) - b.radius) < 0.001)
    // Collinear with centers, pointing from a to b.
    #expect(conn.start.y == 150)
    #expect(conn.end.y == 150)
    #expect(conn.start.x == 100)   // 60 + 40
    #expect(conn.end.x == 290)     // 400 - 110
}

@Test func connectorWorksOffAxis() throws {
    let a = FlowGeometry.Circle(center: .init(x: 0, y: 0), radius: 10)
    let b = FlowGeometry.Circle(center: .init(x: 30, y: 40), radius: 5)   // distance 50
    let conn = try #require(FlowGeometry.connector(from: a, to: b))
    #expect(abs(distance(conn.start, a.center) - 10) < 0.001)
    #expect(abs(distance(conn.end, b.center) - 5) < 0.001)
}

@Test func overlappingCirclesHaveNoConnector() {
    let a = FlowGeometry.Circle(center: .init(x: 0, y: 0), radius: 30)
    let b = FlowGeometry.Circle(center: .init(x: 40, y: 0), radius: 30)
    #expect(FlowGeometry.connector(from: a, to: b) == nil)
}
