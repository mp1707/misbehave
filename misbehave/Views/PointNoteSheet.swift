import MisbehaveKit
import SwiftUI

/// Asked after tapping + or −: a point only goes out with a note, so the partner knows what it is for.
struct PointNoteSheet: View {
    var delta: Int
    var partnerName: String
    var partnerRole: Role
    var partnerMascot: String
    var send: (String) -> Void
    @Environment(\.look) private var look
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var note: String { AppConfig.cleanComment(text) }
    private var isGift: Bool { delta > 0 }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 14) {
                MascotSticker(face: partnerMascot, size: 60, badge: isGift ? "💖" : "💔")
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "\(PushText.signed(delta)) · \(partnerName)")
                        .cozyFont(.title2, weight: .heavy)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text(isGift ? "What was so nice?" : "What went wrong?")
                        .cozyFont(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .ink()

            TextField("Because you…", text: $text, axis: .vertical)
                .lineLimit(1...4)
                .cozyFont(.body)
                .submitLabel(.send)
                .focused($isFocused)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .background(look.palette.card, in: .rect(cornerRadius: 22))
                .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(look.tint(for: partnerRole).opacity(isFocused ? 0.5 : 0.2), lineWidth: 1.5) }
                .onChange(of: text) { _, new in
                    // Return sends instead of starting a new line.
                    guard new.contains("\n") else { return }
                    text = new.replacingOccurrences(of: "\n", with: "")
                    submit()
                }

            Button(action: submit) {
                Label(isGift ? "Give the point" : "Take the point", systemImage: "paperplane.fill")
            }
            .buttonStyle(ProminentButtonStyle(role: partnerRole))
            .disabled(note.isEmpty)
            .opacity(note.isEmpty ? 0.45 : 1)
            .animation(.snappy, value: note.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.top, 26)
        .padding(.bottom, 12)
        .frame(maxHeight: .infinity, alignment: .top)
        .presentationDetents([.height(262)])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .presentationBackground(look.palette.background)
        .onAppear { isFocused = true }
    }

    private func submit() {
        guard !note.isEmpty else { return }
        send(note)
        dismiss()
    }
}
