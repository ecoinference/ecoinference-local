import SwiftUI

/// Explains EcoInference's model-interaction features — the ones users
/// wouldn't discover just by looking at the UI. Deliberately scoped to
/// how you talk to and get results from the model (tool-calling, `use
/// tool`, images, local/cloud routing) — not Settings/Models/About, which
/// are self-explanatory UI, not hidden capabilities.
struct HelpView: View {

    @EnvironmentObject private var appState: AppState

    /// Sends a prefilled example to Chat via the same deep-link mechanism
    /// URL-scheme links use — no separate plumbing needed.
    private func tryExample(_ text: String) {
        appState.deepLink = .openChat(prefill: text)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {

                    // ── How EcoInference answers ────────────────────────────
                    section(title: "How I Answer") {
                        helpRow(
                            icon: "cpu",
                            title: "Local by default",
                            body: "Most questions are answered entirely on your device — private, offline, no data leaves your phone."
                        )
                        helpRow(
                            icon: "cloud.fill",
                            title: "Cloud when it helps",
                            body: "Some requests (current events, very long topics, images the local model can't handle) automatically route to a cloud model instead. Tap the Local/Cloud badge under any reply to see why it was routed there."
                        )
                        helpRow(
                            icon: "arrow.triangle.2.circlepath",
                            title: "Try with Cloud",
                            body: "Not happy with a local answer? Tap \"Try with Cloud\" under it to get a second opinion from the cloud model, using the same conversation so far."
                        )
                        helpRow(
                            icon: "key.fill",
                            title: "Setting up Cloud AI",
                            body: "Cloud answers need your own free Gemini API key. Get one at [aistudio.google.com/apikey](https://aistudio.google.com/apikey), then paste it into Settings → Cloud AI. Local answers always work without one."
                        )
                    }

                    // ── Built-in abilities ──────────────────────────────────
                    section(title: "Built-in Abilities") {
                        Text("Just ask normally — no special phrasing needed. The model decides on its own when one of these would help:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 4)

                        abilityRow("📍", "Location & device", "your GPS location, battery level, flashlight, an SOS blink, opening a map, pre-filling a text message")
                        abilityRow("🌙", "Sky & time", "moon phase, sunrise/sunset, twilight times for any location")
                        abilityRow("🔢", "Math & data", "statistics, curve fitting, distances/bearings, and other calculations")
                        abilityRow("📊", "Charts", "line, bar, and scatter plots drawn from your data")
                        abilityRow("🖼️", "Photo editing", "crop, rotate, filters, brightness/contrast, and more on an attached image")
                        abilityRow("📱", "QR codes", "generate one from any text, link, or Wi-Fi info")

                        Text("Examples: \u{201C}where am I\u{201D}, \u{201C}what's my battery level\u{201D}, \u{201C}plot my sales by month\u{201D}, \u{201C}make this photo black and white\u{201D}.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }

                    // ── use tool ─────────────────────────────────────────────
                    section(title: "Advanced: \u{201C}use tool\u{201D}") {
                        Text("For anything beyond the built-in list above, type \u{201C}use tool\u{201D} followed by what you want. The model writes real Python code and runs it on your device right then — not a preview, an actual result.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        Text("Type \u{201C}list tools\u{201D} to see every available library.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)

                        VStack(spacing: 8) {
                            exampleCard("use tool plot a sine wave")
                            exampleCard("use tool what moon phase is it tonight")
                            exampleCard("use tool calculate the standard deviation of 12, 45, 23, 67, 34, 89")
                        }
                        .padding(.top, 8)
                    }

                    // ── Images ───────────────────────────────────────────────
                    section(title: "Images") {
                        helpRow(
                            icon: "photo.on.rectangle",
                            title: "Attach a photo",
                            body: "Tap the paperclip to attach a photo from your camera or library, then ask a question about it — or ask the model to edit it."
                        )
                        Text("On this device, image understanding works with the Gemma 4 E2B model. (On Android, both E2B and E4B support it.)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 20)
                }
                .padding()
            }
            .background(EcoColors.background)
            .navigationTitle("Help")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: - Building blocks

    @ViewBuilder
    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(EcoColors.nearWhite)
            content()
        }
    }

    // LocalizedStringKey (not String) so call sites can use Markdown link
    // syntax — [text](url) — and get a real tappable link for free.
    private func helpRow(icon: String, title: String, body: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(EcoColors.green)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(body).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func abilityRow(_ emoji: String, _ title: String, _ body: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(emoji).font(.subheadline)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.subheadline.weight(.medium))
                Text(body).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func exampleCard(_ text: String) -> some View {
        Button {
            tryExample(text)
        } label: {
            HStack {
                Text(text)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(EcoColors.nearWhite)
                    .multilineTextAlignment(.leading)
                Spacer()
                Image(systemName: "arrow.up.right.circle.fill")
                    .foregroundStyle(EcoColors.green)
            }
            .padding(12)
            .background(EcoColors.cardDark)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(EcoColors.cardBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
