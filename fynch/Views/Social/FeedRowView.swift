import SwiftUI

struct FeedRowView: View {
    let event: FeedEvent
    var additionalShowCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(event.username)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(eventString(for: event, additionalShowCount: additionalShowCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(relativeTimestamp(event.timestamp))
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}
