//
//  iStatPulseApp.swift
//  iStatPulse
//
//  Created by Hasnain Bukhari on 28/1/2569 BE.
//

import SwiftUI
import SwiftData

@main
struct iStatPulseApp: App {
#if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
#endif

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
#if os(macOS)
        // Menu bar app: no main window; status item and popover are the UI.
        WindowGroup {
            EmptyView()
                .frame(width: 0, height: 0)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 0, height: 0)
        .commandsRemoved()
#else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
#endif
    }
}
