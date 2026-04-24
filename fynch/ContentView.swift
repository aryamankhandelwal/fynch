//
//  ContentView.swift
//  fynch
//
//  Created by Aryaman on 4/8/26.
//

import SwiftUI

struct ContentView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab = 0
    let tmdbService: TMDBService
    let refreshService: RefreshService

    var body: some View {
        Group {
            if appState.isRestoringSession {
                Color(.systemBackground).ignoresSafeArea()
            } else if appState.isLoggedIn {
                TabView(selection: $selectedTab) {
                    HomeView(tmdbService: tmdbService, refreshService: refreshService)
                        .tabItem { Label("My List", systemImage: "tv") }
                        .tag(0)
                    WatchlistView(tmdbService: tmdbService)
                        .tabItem { Label("Watchlist", systemImage: "bookmark") }
                        .tag(1)
                    CombinedFeedView()
                        .tabItem { Label("Feed", systemImage: "person.2") }
                        .tag(2)
                    ProfileView()
                        .tabItem { Label("Profile", systemImage: "person.circle") }
                        .tag(3)
                }
                .transition(.opacity)
                .onChange(of: appState.pendingDeepLinkShowId) { _, newId in
                    if newId != nil { selectedTab = 0 }
                }
            } else {
                LoginView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: appState.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: appState.isRestoringSession)
    }
}

#Preview {
    ContentView(
        tmdbService: TMDBService(bearerToken: ""),
        refreshService: RefreshService()
    )
    .environment(AppState(authService: AuthService(), cloudService: CloudSyncService()))
    .environment(SocialStore())
}
