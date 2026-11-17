#!/usr/bin/env swift
// Run from the repository root with swift scripts/generate-app-icon.swift.
import CoreGraphics
import Foundation
import ImageIO

enum IconError: Error {
    case cannotRender(String)
    case cannotWrite(String)
}

let size = 1024
let extent = CGFloat(size)
let output = URL(fileURLWithPath: "DictusApp/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()

func drawIcon(_ filename: String, background: (CGFloat, CGFloat)?, ink: CGFloat) throws {
    let alphaInfo: CGImageAlphaInfo = background == nil ? .premultipliedLast : .noneSkipLast
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: alphaInfo.rawValue
    ) else {
        throw IconError.cannotRender(filename)
    }

    context.translateBy(x: 0, y: extent)
    context.scaleBy(x: extent, y: -extent)
    if let (start, end) = background {
        let colors = [CGColor(gray: start, alpha: 1), CGColor(gray: end, alpha: 1)]
        guard let gradient = CGGradient(colorsSpace: nil, colors: colors as CFArray, locations: [0, 1]) else {
            throw IconError.cannotRender(filename)
        }
        context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 1, y: 1), options: [])
        context.setStrokeColor(CGColor(gray: ink, alpha: 0.26))
        context.setLineWidth(0.003)
        let rim = CGRect(x: 0.085, y: 0.085, width: 0.83, height: 0.83)
        context.addPath(CGPath(roundedRect: rim, cornerWidth: 0.17, cornerHeight: 0.17, transform: nil))
        context.strokePath()
    }

    // Keep the mark aligned with DictusLogo and the SVG variants in assets/brand.
    let markSide: CGFloat = 0.6
    func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
        CGPoint(x: 0.2 + x * markSide, y: 0.2 + y * markSide)
    }
    context.setStrokeColor(CGColor(gray: ink, alpha: 1))
    context.setLineWidth(markSide * 0.075)
    context.setLineCap(.square)
    context.setLineJoin(.bevel)
    context.addLines(between: [
        point(0.18, 0.89), point(0.18, 0.11), point(0.65, 0.11), point(0.83, 0.29),
        point(0.83, 0.40), point(0.68, 0.55), point(0.18, 0.55)
    ])
    context.move(to: point(0.51, 0.57))
    context.addLine(to: point(0.86, 0.89))
    context.strokePath()

    guard let image = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(
            output.appendingPathComponent(filename) as CFURL, "public.png" as CFString, 1, nil
          ) else {
        throw IconError.cannotWrite(filename)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconError.cannotWrite(filename)
    }
    print("Generated \(filename)")
}

try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try drawIcon("AppIcon-1024.png", background: (1, 0.84), ink: 0.07)
try drawIcon("AppIcon-1024-dark.png", background: (0.135, 0.03), ink: 0.96)
try drawIcon("AppIcon-1024-tinted.png", background: nil, ink: 0)
