#!/usr/bin/env swift
// Renders website/og/card.html to website/public/og.png (1200x630) with WebKit.
// Usage (from the repository root, after `npm ci` in website/): swift website/scripts/make-og.swift
import AppKit
import WebKit

let website = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let card = website.appendingPathComponent("og/card.html")
let output = website.appendingPathComponent("public/og.png")

final class Renderer: NSObject, WKNavigationDelegate {
    let view = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 630))

    func start() {
        view.navigationDelegate = self
        view.loadFileURL(card, allowingReadAccessTo: website)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        waitUntilReady(attempts: 50)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        fail("load failed: \(error.localizedDescription)")
    }

    private func waitUntilReady(attempts: Int) {
        view.evaluateJavaScript("document.title") { value, _ in
            if (value as? String) == "ready" {
                self.snapshot()
            } else if attempts == 0 {
                fail("fonts never finished loading")
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.waitUntilReady(attempts: attempts - 1) }
            }
        }
    }

    private func snapshot() {
        let config = WKSnapshotConfiguration()
        config.rect = NSRect(x: 0, y: 0, width: 1200, height: 630)
        config.snapshotWidth = 1200
        view.takeSnapshot(with: config) { image, error in
            guard let image, let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else {
                fail("snapshot failed: \(error?.localizedDescription ?? "no image")")
                return
            }
            // Re-render at exactly 1200x630 pixels regardless of the display scale.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1200, pixelsHigh: 630, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                       colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            bitmap.draw(in: NSRect(x: 0, y: 0, width: 1200, height: 630))
            NSGraphicsContext.restoreGraphicsState()
            do {
                try rep.representation(using: .png, properties: [:])!.write(to: output)
                print("wrote \(output.path)")
                exit(0)
            } catch {
                fail("write failed: \(error.localizedDescription)")
            }
        }
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-og: \(message)\n".utf8))
    exit(1)
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let renderer = Renderer()
renderer.start()
DispatchQueue.main.asyncAfter(deadline: .now() + 20) { fail("timed out") }
app.run()
