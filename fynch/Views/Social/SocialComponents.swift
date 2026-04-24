import SwiftUI

// MARK: - Relative timestamp

func relativeTimestamp(_ date: Date) -> String {
    let interval = Date().timeIntervalSince(date)
    if interval < 60    { return "just now" }
    if interval < 3600  { return "\(Int(interval / 60))m ago" }
    if interval < 86400 { return "\(Int(interval / 3600))h ago" }
    return "\(Int(interval / 86400))d ago"
}

// MARK: - Event string

func eventString(for event: FeedEvent, additionalShowCount: Int = 0) -> String {
    switch event.type {
    case .started:
        return "started watching \(event.showName)"
    case .watchedEpisode:
        let s = event.season ?? 1
        let e = event.episode ?? 1
        return "Watched Season \(s) Episode \(e) of \(event.showName)"
    case .watchedBatch:
        let count = event.episodeCount ?? 2
        let base = "Watched \(count) episode\(count == 1 ? "" : "s") of \(event.showName)"
        if additionalShowCount > 0 {
            return base + " + \(additionalShowCount) more show\(additionalShowCount == 1 ? "" : "s")"
        }
        return base
    case .finishedSeason:
        return "finished Season \(event.season ?? 1) of \(event.showName)"
    case .finishedShow:
        return "finished \(event.showName)"
    }
}

// MARK: - InitialsCircleView

struct InitialsCircleView: View {
    let username: String
    let size: CGFloat

    private var color: Color {
        Show.palette[abs(username.hashValue) % Show.palette.count]
    }
    private var initial: String { String(username.prefix(1)).uppercased() }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.gradient)
                .frame(width: size, height: size)
            Text(initial)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - NotificationBadgeView

struct NotificationBadgeView: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.system(size: 17))
                if unreadCount > 0 {
                    Text(unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 2)
                        .background(.red, in: Capsule())
                        .offset(x: 8, y: -8)
                }
            }
        }
    }
}
