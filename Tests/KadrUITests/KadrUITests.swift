import Testing
import Kadr
@testable import KadrUI
import CoreGraphics

@Test func packageBuildsAndLoads() {
    _ = KadrUI.self
}

/// Sanity check that the Kadr v0.4 public preview/layout surface is reachable
/// through the dependency. If Kadr is downgraded below 0.4.0, this fails to compile.
@Test func kadrV04SurfaceIsReachable() {
    let frame = Kadr.Layout.resolveFrame(
        position: .center,
        size: .normalized(width: 0.5, height: 0.5),
        in: CGSize(width: 1080, height: 1920)
    )
    #expect(frame.size.width == 540)
    #expect(frame.size.height == 960)
}
