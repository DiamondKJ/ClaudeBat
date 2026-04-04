#!/usr/bin/env swift
// Generates ClaudeBat app icons at all required sizes.
// Usage: swift scripts/generate-app-icon.swift
//
// macOS applies its own superellipse mask to app icons.
// We just fill the full square with the base color and draw the bat.

import AppKit
import CoreGraphics

// MARK: - Pixel Bat Grid (31x13, from PixelBatView — default expression)

let batGrid: [[Int]] = [
    [0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,0,1,1,1,0,1,1,1,1,1,0,1,1,1,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,1,1,1,1,0,1,1,1,1,1,0,1,1,1,1,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,1,1,1,1,1,0,1,1,1,1,1,0,1,1,1,1,1,0,0,0,0,0,0,0],
    [0,0,0,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,0,0,1,1,1,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,1,0,0,1,1,1],
    [1,1,0,0,0,0,1,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,1,0,0,0,0,1,1],
    [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
]

let batCols = 31
let batRows = 13

let baseR: CGFloat = 0x1A / 255.0
let baseG: CGFloat = 0x12 / 255.0
let baseB: CGFloat = 0x10 / 255.0

let accentR: CGFloat = 0xE8 / 255.0
let accentG: CGFloat = 0x73 / 255.0
let accentB: CGFloat = 0x4A / 255.0

// MARK: - Icon Rendering

func renderIcon(size: Int) -> NSImage {
    let s = CGFloat(size)

    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()

    guard let ctx = NSGraphicsContext.current?.cgContext else {
        fatalError("No graphics context")
    }

    // Fill entire square with base color — macOS applies its own mask
    ctx.setFillColor(CGColor(red: baseR, green: baseG, blue: baseB, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))

    // Calculate pixel size to center the bat
    let pixelSize = (28.0 / 1024.0) * s
    let batWidth = CGFloat(batCols) * pixelSize
    let batHeight = CGFloat(batRows) * pixelSize
    let offsetX = (s - batWidth) / 2.0
    let offsetY = (s - batHeight) / 2.0

    // Draw bat pixels
    ctx.setFillColor(CGColor(red: accentR, green: accentG, blue: accentB, alpha: 1))
    for row in 0..<batRows {
        for col in 0..<batCols {
            guard batGrid[row][col] == 1 else { continue }
            let x = offsetX + CGFloat(col) * pixelSize
            let y = s - offsetY - CGFloat(row + 1) * pixelSize
            let rect = CGRect(x: x, y: y, width: pixelSize + 0.5, height: pixelSize + 0.5)
            ctx.fill(rect)
        }
    }

    image.unlockFocus()
    return image
}

func savePNG(_ image: NSImage, to path: String) {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        print("Failed to create PNG for \(path)")
        return
    }
    do {
        try png.write(to: URL(fileURLWithPath: path))
        print("Saved: \(path) (\(Int(image.size.width))x\(Int(image.size.height)))")
    } catch {
        print("Error writing \(path): \(error)")
    }
}

// MARK: - Main

let outputDir = "ClaudeBat/Assets.xcassets/AppIcon.appiconset"
let sizes = [16, 32, 64, 128, 256, 512, 1024]

for size in sizes {
    let image = renderIcon(size: size)
    savePNG(image, to: "\(outputDir)/icon_\(size)x\(size).png")
}

print("\nDone! Generated \(sizes.count) icon sizes.")
