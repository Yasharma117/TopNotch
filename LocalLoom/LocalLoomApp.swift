//
//  LocalLoomApp.swift
//  LocalLoom
//
//  Created by Yash Sharma on 28/04/26.
//

import SwiftUI
import CoreData

@main
struct LocalLoomApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
