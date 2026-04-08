//
//  fynchApp.swift
//  fynch
//
//  Created by Aryaman on 4/8/26.
//

import SwiftUI

@main
struct fynchApp: App {
    @State private var appState = AppState()
    private let tmdbService = TMDBService(bearerToken: Secrets.tmdbBearerToken)

    var body: some Scene {
        WindowGroup {
            ContentView(tmdbService: tmdbService)
                .environment(appState)
        }
    }
}
