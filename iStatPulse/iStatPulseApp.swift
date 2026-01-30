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
        MenuBarExtra {
            PopoverContentView()
                .frame(width: 384, height: 784)
        } label: {
            MenuBarLabelView()
        }
        .menuBarExtraStyle(.window)
#else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
#endif
    }
}
