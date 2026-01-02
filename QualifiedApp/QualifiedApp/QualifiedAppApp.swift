//
//  QualifiedAppApp.swift
//  QualifiedApp
//
//  Main entry point for the Qualified macOS app
//

import SwiftUI

@main
struct QualifiedAppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}
