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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }

        button.image = NSImage(systemSymbolName: "chart.bar.doc.horizontal", accessibilityDescription: "iStat Pulse")
        button.action = #selector(togglePopover)
        button.target = self

        popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverContentView())
        popover.animates = true

        // Hide the default window so only the menu bar is visible.
        DispatchQueue.main.async { [weak self] in
            NSApp.windows.forEach { $0.close() }
        }
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
}
#endif
