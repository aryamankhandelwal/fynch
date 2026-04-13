import SwiftUI

struct WatchlistRowView: View {
    let show: Show
    let unwatchedCount: Int

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "chevron.left")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .fill(show.posterColor.gradient)
                    .frame(width: 48, height: 48)
                Text(show.title.prefix(1))
                    .font(.msTitle2)
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(show.title)
                    .font(.msHeadline)
                Text("\(unwatchedCount) episode\(unwatchedCount == 1 ? "" : "s")")
                    .font(.msSubheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
