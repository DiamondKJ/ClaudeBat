#!/usr/bin/env swift
// Generates a winking pixel bat PNG for the README.

import AppKit
import CoreGraphics

let batWinking: [[Int]] = [
    [0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,0,0,0,1,1,1,0,0,0,1,1,1,0,0,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,0,1,1,1,0,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,0,1,1,1,1,0,1,1,1,1,1,0,0,1,1,1,0,0,0,0,0,0,0,0],
    [0,0,0,0,0,0,0,1,1,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,0,0,0,0,0,0,0],
    [0,0,0,1,0,0,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,0,0,1,0,0,0],
    [0,0,1,1,1,0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0,1,1,1,0,0],
    [0,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,0],
    [1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,0,0,1,1,1,1,1,1,1,1,1,1],
    [1,1,1,0,0,1,1,1,0,0,0,0,0,1,1,1,1,1,0,0,0,0,0,1,1,1,0,0,1,1,1],
    [1,1,0,0,0,0,1,0,0,0,0,0,0,0,1,1,1,0,0,0,0,0,0,0,1,0,0,0,0,1,1],
    [1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1],
]

let cols = 31, rows = 13
let pixelSize: CGFloat = 12
let padX: CGFloat = 40, padY: CGFloat = 30
let w = CGFloat(cols) * pixelSize + padX * 2
let h = CGFloat(rows) * pixelSize + padY * 2

let image = NSImage(size: NSSize(width: w, height: h))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError() }

// Background
ctx.setFillColor(CGColor(red: 0x1A/255, green: 0x12/255, blue: 0x10/255, alpha: 1))
ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))

// Bat pixels
ctx.setFillColor(CGColor(red: 0xE8/255, green: 0x73/255, blue: 0x4A/255, alpha: 1))
for row in 0..<rows {
    for col in 0..<cols {
        guard batWinking[row][col] == 1 else { continue }
        let x = padX + CGFloat(col) * pixelSize
        let y = h - padY - CGFloat(row + 1) * pixelSize
        ctx.fill(CGRect(x: x, y: y, width: pixelSize + 0.5, height: pixelSize + 0.5))
    }
}
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else { fatalError() }

let outPath = "assets/bat-winking.png"
try! FileManager.default.createDirectory(atPath: "assets", withIntermediateDirectories: true)
try! png.write(to: URL(fileURLWithPath: outPath))
print("Saved: \(outPath) (\(Int(w))x\(Int(h)))")
