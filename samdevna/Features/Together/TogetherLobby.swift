import CoreGraphics
import SwiftUI

/// Start or join a "Fix it together" session, and replay saved repair memories.
struct TogetherLobby: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var joinFailed = false
    @State private var memories: [RepairMemory] = []
    private let store = RepairMemoryStore()

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Someone who knows how, seeing what you see.")
                            .font(Typo.headline)
                        Text("Share a code. A helper joins from their phone or any browser, taps the part, and SAM 3.1 outlines it on your screen. You each hear the other in your own language.")
                            .font(Typo.footnote)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(.vertical, Space.xxs)
                    Button {
                        model.startTogether()
                        dismiss()
                    } label: {
                        Label("Start a session (I'm fixing)", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(model.relay == nil || !model.hasKey)
                    HStack {
                        TextField("Join code or link", text: $code)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .font(Typo.mono)
                        Button("Join") {
                            if model.joinTogether(code) { dismiss() } else { joinFailed = true }
                        }
                        .disabled(code.isEmpty || model.relay == nil)
                    }
                    Button {
                        model.startTogether(demo: true)
                        dismiss()
                    } label: {
                        Label("Two-device demo (scripted helper)", systemImage: "play.rectangle")
                    }
                } footer: {
                    if model.relay == nil {
                        Text("Set a relay URL in Settings first (your Cloudflare Worker, or http://<your-mac>:8787 for `npm start` on the same Wi-Fi). The demo works without one.")
                    } else if !model.hasKey {
                        Text("Starting a session needs your Meta API key on this phone: SAM 3.1, Muse Voice Transcribe and Muse Spark run here, never on the helper's device.")
                    } else {
                        Text("Camera: \(model.cameraSource.label). Change it in Settings.")
                    }
                }

                if !memories.isEmpty {
                    Section("Repair memory") {
                        ForEach(memories) { memory in
                            Button {
                                model.replay(memory, photo: UIImage(contentsOfFile: store.photoURL(for: memory).path))
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(memory.title).font(Typo.bodyEmphasis)
                                    Text("\(memory.plan.steps.count) steps · with \(memory.participants.dropFirst().joined(separator: ", ")) · \(memory.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                        .font(Typo.footnote)
                                        .foregroundStyle(Palette.textSecondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            offsets.map { memories[$0] }.forEach(store.delete)
                            memories.remove(atOffsets: offsets)
                        }
                    }
                }
            }
            .navigationTitle("Fix it together")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .alert("That code doesn't look right", isPresented: $joinFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Codes are 4–8 letters and numbers, like K7M2QX, or paste the share link.")
            }
            .onAppear { memories = store.all() }
        }
    }
}
