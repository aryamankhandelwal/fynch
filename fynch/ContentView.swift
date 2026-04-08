//
//  ContentView.swift
//  fynch
//
//  Created by Aryaman on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    let tmdbService: TMDBService

    var body: some View {
        HomeView(tmdbService: tmdbService)
    }
}

#Preview {
    ContentView(tmdbService: TMDBService(bearerToken: ""))
        .environment(AppState())
}
