import MisbehaveKit
import SwiftUI

/// What a look editor changes: the app's own look on this iPhone, or a connection's shared one.
enum LookTarget: Equatable {
    case app
    case connection(String)
}

/// Colours, background, font, celebration and, for a connection, both mascots. Every tap applies
/// right away and the editor itself wears the look, so it doubles as the preview.
struct LookEditor: View {
    var target: LookTarget
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var choosingMascotFor: Side?
    /// Counts up to set off the celebration in the preview.
    @State private var cheer = 0

    private var connection: Connection? {
        if case .connection(let id) = target { model.connection(id) } else { nil }
    }

    private var look: Look { connection?.look ?? model.state.look }
    private var role: Role { connection?.myRole ?? model.state.profile?.role ?? .goodgirl }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 26) {
                    LookPreview(connection: connection, role: role, cheer: cheer)
                    if let connection {
                        mascots(connection)
                    }
                    section("Colours") {
                        ForEach(Palette.allCases) { palette in
                            Chip(name: palette.name, isSelected: look.palette == palette, isRound: true) {
                                change { $0.palette = palette }
                            } face: {
                                Circle()
                                    .fill(palette.gradient(for: role))
                                    .overlay { Text(verbatim: palette.emoji).font(.system(size: 24)) }
                            }
                        }
                    }
                    section("Background") {
                        ForEach(Pattern.allCases) { pattern in
                            Chip(name: pattern.name, isSelected: look.pattern == pattern) {
                                change { $0.pattern = pattern }
                            } face: {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(look.gradient(for: role))
                                    .overlay { PawPattern(pattern, size: 13).foregroundStyle(.white.opacity(0.55)) }
                                    .clipShape(.rect(cornerRadius: 18))
                            }
                        }
                    }
                    section("Font") {
                        ForEach(Typeface.allCases) { typeface in
                            Chip(name: typeface.name, isSelected: look.typeface == typeface) {
                                change { $0.typeface = typeface }
                            } face: {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(look.palette.card)
                                    .overlay {
                                        Text(verbatim: "Aa")
                                            .font(typeface.font(size: 26, weight: .bold))
                                            .fontDesign(typeface.design)
                                            .foregroundStyle(look.tint(for: role))
                                    }
                            }
                        }
                    }
                    section("Celebration") {
                        ForEach(Burst.allCases) { burst in
                            Chip(name: burst.name, isSelected: look.burst == burst) {
                                change { $0.burst = burst }
                                cheer += 1
                            } face: {
                                RoundedRectangle(cornerRadius: 18)
                                    .fill(look.palette.card)
                                    .overlay {
                                        Text(verbatim: burst.up.prefix(3).joined())
                                            .font(.system(size: 18))
                                    }
                            }
                        }
                    }

                    VStack(spacing: 14) {
                        Text(footer)
                            .cozyFont(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .ink()
                        Button("Back to the default look") { reset() }
                            .cozyFont(.subheadline, weight: .semibold)
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .padding(16)
            }
            .background { CozyBackground() }
            .navigationTitle("Customize")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $choosingMascotFor) { side in
                if let connection {
                    MascotPicker(connection: connection, side: side)
                }
            }
        }
        .themed(look)
        .animation(.snappy, value: look)
        .sensoryFeedback(.selection, trigger: look)
    }

    private var footer: LocalizedStringKey {
        if let connection {
            connection.isDemo
                ? "In a real connection both of you see this look: here, in your widgets and in the notification pictures."
                : "\(connection.partnerDisplayName) sees this look too: here, in the widgets and in the notification pictures. Either of you can change it."
        } else {
            "This look is for the overview and everything outside a connection, only on this iPhone. The app icon follows the colours."
        }
    }

    @ViewBuilder
    private func mascots(_ connection: Connection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Mascots")
            HStack(spacing: 14) {
                mascotButton(face: connection.myMascot, name: String(localized: "You"), role: connection.myRole) {
                    choosingMascotFor = connection.side
                }
                mascotButton(face: connection.partnerMascot, name: connection.partnerDisplayName, role: connection.resolvedPartnerRole) {
                    choosingMascotFor = connection.side.other
                }
            }
        }
    }

    private func mascotButton(face: String, name: String, role: Role, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                MascotSticker(face: face, size: 70, onGradient: true)
                    .hop(on: face)
                Text(verbatim: name)
                    .cozyFont(.subheadline, weight: .bold)
                    .lineLimit(1)
                Text("Tap to change")
                    .cozyFont(.caption)
                    .opacity(0.85)
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .gradientCard(role, cornerRadius: 26)
        }
        .buttonStyle(SquishyButtonStyle())
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(title)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) { content() }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -16)
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .cozyFont(.headline, weight: .heavy)
            .ink()
            .padding(.horizontal, 4)
    }

    private func change(_ body: (inout Look) -> Void) {
        switch target {
        case .app: model.updateAppLook(body)
        case .connection(let id): model.updateStyle(of: id) { body(&$0.look) }
        }
    }

    private func reset() {
        switch target {
        case .app:
            model.updateAppLook { $0 = Look() }
        case .connection(let id):
            model.updateStyle(of: id) {
                $0.look = Look()
                $0.ownerMascot = nil
                $0.participantMascot = nil
            }
        }
    }
}

extension Side: @retroactive Identifiable {
    public var id: String { rawValue }
}

/// A small card in a horizontal row of options.
private struct Chip<Face: View>: View {
    var name: String
    var isSelected: Bool
    var isRound = false
    var action: () -> Void
    @ViewBuilder var face: Face
    @Environment(\.look) private var look

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                face
                    .frame(width: 64, height: 64)
                    .overlay {
                        if isSelected {
                            RoundedRectangle(cornerRadius: isRound ? 37 : 21)
                                .strokeBorder(look.palette.ink, lineWidth: 3)
                                .padding(-5)
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white, look.palette.ink)
                                .offset(x: 9, y: -9)
                                .transition(.scale.combined(with: .opacity))
                        }
                    }
                    .shadow(color: look.palette.shadow, radius: 6, y: 3)
                Text(verbatim: name)
                    .cozyFont(.caption, weight: isSelected ? .heavy : .medium)
                    .lineLimit(1)
                    .ink()
            }
            .frame(width: 78)
            .padding(.top, 6)
        }
        .buttonStyle(SquishyButtonStyle())
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A miniature of a connection card in the look being edited.
private struct LookPreview: View {
    var connection: Connection?
    var role: Role
    var cheer: Int
    @Environment(\.look) private var look

    private var score: Int { connection?.myScore ?? 7 }

    var body: some View {
        HStack(spacing: 14) {
            MascotSticker(face: connection?.myMascot ?? role.emoji, size: 74, badge: Mood(score: score).badge, onGradient: true)
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: connection?.partnerDisplayName ?? "misbehave")
                    .cozyFont(.headline, weight: .semibold)
                    .lineLimit(1)
                Text(score, format: .number)
                    .cozyFont(size: 46, weight: .heavy)
                Text(verbatim: PushText.pointsLabel(count: score, role: role))
                    .cozyFont(.subheadline, weight: .bold)
            }
            Spacer(minLength: 0)
            if let connection {
                MascotSticker(face: connection.partnerMascot, size: 52, onGradient: true)
                    .rotationEffect(.degrees(8))
            }
        }
        .foregroundStyle(.white)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gradientCard(role)
        .emojiBurst(on: cheer)
        .accessibilityHidden(true)
    }
}

/// Every mascot to choose from, plus any emoji typed in.
private struct MascotPicker: View {
    var connection: Connection
    var side: Side
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""

    private var role: Role { side == connection.side ? connection.myRole : connection.resolvedPartnerRole }
    private var current: String { side == connection.side ? connection.myMascot : connection.partnerMascot }
    private var name: String { side == connection.side ? String(localized: "you") : connection.partnerDisplayName }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MascotSticker(face: Mascots.emoji(in: typed) ?? current, size: 96)
                        .hop(on: current)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 56), spacing: 10)], spacing: 10) {
                        ForEach(Mascots.all, id: \.self) { emoji in
                            Button {
                                choose(emoji)
                            } label: {
                                MascotSticker(face: emoji, size: 56)
                                    .overlay {
                                        if emoji == current {
                                            Circle().strokeBorder(.tint, lineWidth: 3)
                                        }
                                    }
                            }
                            .buttonStyle(SquishyButtonStyle())
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Or any other emoji")
                            .cozyFont(.headline, weight: .semibold)
                            .ink()
                        HStack {
                            TextField("Type one emoji", text: $typed)
                                .cozyFont(.title3)
                                .submitLabel(.done)
                                .onSubmit { if let emoji = Mascots.emoji(in: typed) { choose(emoji) } }
                            Button("Use") { if let emoji = Mascots.emoji(in: typed) { choose(emoji) } }
                                .disabled(Mascots.emoji(in: typed) == nil)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .softCard(cornerRadius: 20)
                    }
                    Button("Back to \(role.emoji)") { choose(role.emoji) }
                        .cozyFont(.subheadline, weight: .semibold)
                }
                .padding(20)
            }
            .background { CozyBackground() }
            .navigationTitle(Text("Mascot for \(name)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func choose(_ emoji: String) {
        let role = role
        model.updateStyle(of: connection.id) { $0.setMascot(emoji == role.emoji ? nil : emoji, of: side) }
        dismiss()
    }
}
