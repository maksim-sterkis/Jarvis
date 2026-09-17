//
//  JarvisLogoView.swift
//  Jarvis
//

import SwiftUI

struct JarvisLogoShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let size = min(rect.width, rect.height)
        let ox = rect.minX + (rect.width - size) / 2.0
        let oy = rect.minY + (rect.height - size) / 2.0

        func p(_ xNorm: CGFloat, _ yNorm: CGFloat) -> CGPoint {
            CGPoint(x: ox + xNorm * size, y: oy + yNorm * size)
        }

        // Normalized coordinates (0,0 is top-left)
        let yTop: CGFloat = 0.244
        let yArmBottom: CGFloat = 0.342
        let yHookTop: CGFloat = 0.537
        let yBottom: CGFloat = 0.732
        let chamfer: CGFloat = 0.088
        let ribW: CGFloat = 0.088

        let xArmLeft: CGFloat = 0.459
        let xRight: CGFloat = 0.635
        let xLeft: CGFloat = 0.371

        // 1. J Ribbon
        path.move(to: p(xArmLeft, yTop))
        path.addLine(to: p(xRight, yTop))
        path.addLine(to: p(xRight, yBottom - chamfer))
        path.addLine(to: p(xRight - chamfer, yBottom))
        path.addLine(to: p(xLeft, yBottom))
        path.addLine(to: p(xLeft, yHookTop))
        path.addLine(to: p(xLeft + ribW, yHookTop))
        path.addLine(to: p(xLeft + ribW, yBottom - ribW))
        path.addLine(to: p(xRight - chamfer - (ribW * 0.414), yBottom - ribW))
        path.addLine(to: p(xRight - ribW, yBottom - chamfer - (ribW * 0.414)))
        path.addLine(to: p(xRight - ribW, yArmBottom))
        path.addLine(to: p(xArmLeft, yArmBottom))
        path.closeSubpath()

        // 2. Chevron '>' (top-tier aligned with J's top and hook)
        let vertexX: CGFloat = 0.317
        let centerY = (yTop + yHookTop) / 2.0
        let spanY = (yHookTop - yTop) / 2.0
        path.move(to: p(vertexX - spanY, yTop))
        path.addLine(to: p(vertexX, centerY))
        path.addLine(to: p(vertexX - spanY, yHookTop))

        // 3. Underscore '_' (flush with J's baseline)
        let xUnderStart: CGFloat = 0.688
        let xUnderEnd: CGFloat = 0.825
        path.move(to: p(xUnderStart, yBottom))
        path.addLine(to: p(xUnderEnd, yBottom))

        return path
    }
}

struct JarvisLogoView: View {
    var size: CGFloat = 28
    var showBackground: Bool = true
    var color: Color = .white

    var body: some View {
        let strokeW = max(1.5, size * 0.038)

        ZStack {
            if showBackground {
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            }

            JarvisLogoShape()
                .stroke(
                    color,
                    style: StrokeStyle(
                        lineWidth: strokeW,
                        lineCap: .square,
                        lineJoin: .miter,
                        miterLimit: 10
                    )
                )
                .frame(width: size, height: size)
        }
        .frame(width: size, height: size)
    }
}
