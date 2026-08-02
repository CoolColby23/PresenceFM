import SwiftUI

struct QueueCorrection: Identifiable {
    let id: UUID
    var title: String
    var artist: String
    var album: String
}

struct QueueCorrectionView: View {
    @Environment(\.dismiss) private var dismiss
    @State var draft: QueueCorrection
    let save: (QueueCorrection) -> Void

    private var canSave: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !draft.artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Correct Scrobble Metadata").font(.title2.bold())
            Text(
                "Review the rejected metadata before retrying. PresenceFM keeps the original listen time and duplicate protection."
            )
            .foregroundStyle(.secondary)
            Form {
                TextField("Title", text: $draft.title)
                    .accessibilityIdentifier("queue.correction.title")
                TextField("Artist", text: $draft.artist)
                    .accessibilityIdentifier("queue.correction.artist")
                TextField("Album (optional)", text: $draft.album)
                    .accessibilityIdentifier("queue.correction.album")
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save and Retry") { save(draft) }
                    .disabled(!canSave)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("queue.correction.save")
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}
