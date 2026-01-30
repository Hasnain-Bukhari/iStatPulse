//
//  AppDelegate.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

#if os(macOS)
import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var debugWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        if let image = NSImage(systemSymbolName: "chart.bar.doc.horizontal", accessibilityDescription: "iStat Pulse") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "iSP"
        }
        if button.title.isEmpty {
            button.title = "iSP"
        }
        button.toolTip = "iStat Pulse"
        button.action = #selector(togglePopover)
        button.target = self

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 560)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverContentView())
        popover.animates = true

        // Hide the default window so only the menu bar is visible.
        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach { $0.close() }
        }

        #if DEBUG
        // Debug fallback: show a window if the status item isn't visible.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self = self else { return }
            if self.statusItem.button == nil || self.statusItem.button?.window == nil {
                self.showDebugWindow()
            }
        }
        #endif
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    private func showDebugWindow() {
        let content = NSHostingView(rootView: PopoverContentView())
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 640),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "iStat Pulse (Debug)"
        window.contentView = content
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        debugWindow = window
    }
}
#endif
