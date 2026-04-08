//
//  fynchApp.swift
//  fynch
//
//  Created by Aryaman on 4/8/26.
//

import SwiftUI
import BackgroundTasks

@main
struct fynchApp: App {
    private let authService: AuthService
    private let cloudService: CloudSyncService
    private let tmdbService: TMDBService
    private let refreshService: RefreshService
    @State private var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth  = AuthService()
        let cloud = CloudSyncService()
        authService    = auth
        cloudService   = cloud
        tmdbService    = TMDBService(bearerToken: Secrets.tmdbBearerToken)
        refreshService = RefreshService()
        _appState      = State(wrappedValue: AppState(authService: auth, cloudService: cloud))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(tmdbService: tmdbService, refreshService: refreshService)
                .environment(appState)
                .task {
                    // Attempt to restore a saved session from Keychain on launch
                    if let saved = KeychainService.load() {
                        let session = (try? await authService.refreshIfNeeded(saved)) ?? saved
                        await appState.restoreSession(session)
                        await appState.loadUserData()
                    }
                    appState.isRestoringSession = false
                }
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await appState.refreshAllShows(
                        service: tmdbService,
                        refreshService: refreshService,
                        isManual: false
                    )
                }
                scheduleBackgroundRefreshIfNeeded()
            }
        }
        .backgroundTask(.appRefresh("com.fynch.refresh")) {
            await appState.refreshAllShows(
                service: tmdbService,
                refreshService: refreshService,
                isManual: false
            )
            scheduleNextBackgroundRefresh()
        }
    }

    nonisolated private func scheduleBackgroundRefreshIfNeeded() {
        let request = BGAppRefreshTaskRequest(identifier: "com.fynch.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 86_400)
        try? BGTaskScheduler.shared.submit(request)
    }

    nonisolated private func scheduleNextBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: "com.fynch.refresh")
        request.earliestBeginDate = Date(timeIntervalSinceNow: 86_400)
        try? BGTaskScheduler.shared.submit(request)
    }
}
