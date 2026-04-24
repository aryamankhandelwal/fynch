//
//  fynchApp.swift
//  fynch
//
//  Created by Aryaman on 4/8/26.
//

import SwiftUI
import BackgroundTasks
import UserNotifications

@main
struct fynchApp: App {
    private let authService: AuthService
    private let cloudService: CloudSyncService
    private let socialSyncService: SocialSyncService
    private let tmdbService: TMDBService
    private let refreshService: RefreshService
    private let notificationDelegate: NotificationDelegate
    @State private var appState: AppState
    @State private var socialStore = SocialStore()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let auth  = AuthService()
        let cloud = CloudSyncService()
        authService       = auth
        cloudService      = cloud
        socialSyncService = SocialSyncService()
        tmdbService       = TMDBService(bearerToken: Secrets.tmdbBearerToken)
        refreshService    = RefreshService()
        let state = AppState(authService: auth, cloudService: cloud)
        _appState = State(wrappedValue: state)
        let delegate = NotificationDelegate(appState: state)
        notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate
        BestiaryFonts.register()
        BestiaryFonts.applyNavigationBarAppearance()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(tmdbService: tmdbService, refreshService: refreshService)
                .environment(appState)
                .environment(socialStore)
                .preferredColorScheme(.dark)
                .task {
                    appState.socialStore = socialStore
                    if let saved = KeychainService.load() {
                        let session = (try? await authService.refreshIfNeeded(saved)) ?? saved
                        appState.restoreSession(session)
                        await appState.loadUserData()
                    }
                    appState.isRestoringSession = false
                }
                .onChange(of: appState.currentUser?.userId) { _, newUserId in
                    if let userId = newUserId, let session = appState.currentUser {
                        socialStore.socialSyncService = socialSyncService
                        socialStore.currentUserId    = userId
                        socialStore.currentUsername  = session.username
                        socialStore.currentIdToken   = session.idToken
                        Task {
                            await socialSyncService.saveUserProfile(
                                userId: userId,
                                username: session.username,
                                idToken: session.idToken
                            )
                            await socialStore.loadFromFirestore()
                        }
                    } else {
                        // Signed out — clear social identity
                        socialStore.currentUserId   = ""
                        socialStore.currentUsername = ""
                        socialStore.currentIdToken  = ""
                    }
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

// MARK: - Notification Delegate

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    private weak var appState: AppState?

    init(appState: AppState) {
        self.appState = appState
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let showId = response.notification.request.content.userInfo["showId"] as? String {
            Task { @MainActor in
                self.appState?.pendingDeepLinkShowId = showId
            }
        }
        completionHandler()
    }
}
