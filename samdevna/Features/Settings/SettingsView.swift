import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var keyDraft = ""
    @State private var hasUserKey = SecretStore.hasUserKey
    @State private var connection: ConnectionState = .unknown

    private enum ConnectionState: Equatable {
        case unknown, checking, ok(Int), failed(String)
    }

    var body: some View {
        NavigationStack {
            Form {
                apiSection
                cameraSection
                togetherSection
                demoSection
                voiceSection
                Section("Appearance") {
                    Picker("Theme", selection: $model.appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                scopeSection
                pipelineSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("settings.done")
                }
            }
        }
    }

    // MARK: Sections

    private var cameraSection: some View {
        Section {
            Picker("Camera source", selection: $model.cameraSource) {
                ForEach(CameraSource.allCases) { source in
                    Label(source.label, systemImage: source.symbol).tag(source)
                }
            }
            .pickerStyle(.segmented)
            if model.cameraSource == .glasses {
                LabeledContent("Glasses", value: model.glasses.state.label)
                if model.glasses.state.isStreaming {
                    LabeledContent("Frame rate", value: String(format: "%.0f fps", model.glasses.fps))
                }
                Button("Connect Ray-Ban Meta (opens Meta AI)") { Task { await model.glasses.connect() } }
                    .disabled(!GlassesCameraService.isLinked)
                Button("Start glasses camera") { Task { await model.glasses.start() } }
                    .disabled(!GlassesCameraService.isLinked)
                if GlassesCameraService.mockAvailable {
                    Button("Use Mock Device (simulated glasses · sink clip)") { model.glasses.useMockDevice(scene: "sink") }
                    Button("Use Mock Device (simulated glasses · bike clip)") { model.glasses.useMockDevice(scene: "bike") }
                    if model.glasses.usingMock {
                        Button("Stop Mock Device", role: .destructive) { model.glasses.stopMockDevice() }
                    }
                }
            }
        } header: {
            Text("Camera")
        } footer: {
            Text(model.cameraSource == .glasses
                 ? "Uses the Meta Wearables Device Access Toolkit. Turn on Developer Mode in Meta AI (Settings → your glasses → Developer Mode). Guidance plays through the glasses' speakers over Bluetooth. Mock Device (debug builds) streams a recorded point-of-view clip instead of real glasses."
                 : "Lens, the guide and Fix it together use the iPhone's back camera.")
        }
    }

    private var togetherSection: some View {
        Section {
            TextField("Your name (shown to helpers)", text: $model.displayName)
            TextField("Relay URL, e.g. https://fixit-together.you.workers.dev", text: $model.relayURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !model.relayURL.isEmpty, model.relay == nil {
                Text("That isn't an http(s) URL.").font(Typo.footnote).foregroundStyle(Palette.coral)
            }
        } header: {
            Text("Fix it together")
        } footer: {
            Text("The relay only forwards frames, taps and text. Deploy together/relay to Cloudflare (free) or run `npm start` on a computer on the same Wi-Fi. Your Meta API key stays on this phone.")
        }
    }

    private var apiSection: some View {
        Section {
            LabeledContent("Status") {
                Label(model.hasKey ? (hasUserKey ? "Key saved" : "Using build key") : "No key",
                      systemImage: model.hasKey ? "checkmark.seal.fill" : "key")
                    .foregroundStyle(model.hasKey ? Palette.teal : Palette.saffron)
            }
            SecureField(hasUserKey ? "Replace key" : "Paste your Meta Model API key", text: $keyDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.password)
                .accessibilityIdentifier("settings.key")
            if !keyDraft.isEmpty {
                Button("Save key to Keychain") {
                    SecretStore.saveUserKey(keyDraft)
                    keyDraft = ""
                    hasUserKey = SecretStore.hasUserKey
                    model.refreshKey()
                    connection = .unknown
                    Haptics.success()
                }
            }
            if hasUserKey {
                Button("Remove saved key", role: .destructive) {
                    SecretStore.saveUserKey("")
                    hasUserKey = false
                    model.refreshKey()
                    connection = .unknown
                }
            }
            Button {
                Task { await testConnection() }
            } label: {
                HStack {
                    Text("Test connection")
                    Spacer()
                    connectionBadge
                }
            }
            .disabled(!model.hasKey || connection == .checking)
            .accessibilityIdentifier("settings.test")
        } header: {
            Text("Meta Model API")
        } footer: {
            Text("Stored in this device's Keychain and sent only to api.meta.ai. Test connection calls GET /v1/models.")
        }
    }

    @ViewBuilder
    private var connectionBadge: some View {
        switch connection {
        case .unknown: EmptyView()
        case .checking: ProgressView()
        case .ok(let count):
            Label("\(count) models", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.teal).font(Typo.caption)
        case .failed:
            Label("Failed", systemImage: "xmark.circle.fill").foregroundStyle(Palette.coral).font(Typo.caption)
        }
    }

    private var demoSection: some View {
        Section {
            Toggle("Demo replay for samples", isOn: $model.preferReplay)
                .accessibilityIdentifier("settings.replay")
        } footer: {
            Text(model.hasKey
                 ? "On: the built-in samples play a scripted run with no network calls. Off: samples go through the live Meta pipeline."
                 : "With no key, the built-in samples always play a scripted run. Your own photos need a key.")
        }
    }

    private var voiceSection: some View {
        Section {
            Toggle("Hands-free listening", isOn: $model.handsFree)
            Picker("Language", selection: $model.language) {
                ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
            }
            VStack(alignment: .leading) {
                Text("Speaking speed")
                Slider(value: $model.speechRate, in: 0.38...0.6) {
                    Text("Speaking speed")
                } minimumValueLabel: {
                    Image(systemName: "tortoise.fill")
                } maximumValueLabel: {
                    Image(systemName: "hare.fill")
                }
            }
            Button("Preview voice") {
                model.voice.speak("Step one. Put the bucket under the trap.", language: model.language, rate: Float(model.speechRate))
            }
        } header: {
            Text("Voice guide")
        } footer: {
            Text("Muse Voice Transcribe hears you in your language. Steps are read aloud by the on-device voice, because Meta's Model API has no text-to-speech; nothing is sent anywhere for that.")
        }
    }

    private var scopeSection: some View {
        Section {
            Label("Plumbing, bikes, small appliances, furniture and fixtures", systemImage: "checkmark.circle.fill")
                .labelStyle(TintedIconLabelStyle(tint: Palette.teal))
            Label("Stops for gas, mains electrics, refrigerant, airbags, fuel leaks and structural damage", systemImage: "hand.raised.fill")
                .labelStyle(TintedIconLabelStyle(tint: Palette.coral))
            Label("Never assesses people, pets, injuries or health", systemImage: "xmark.circle.fill")
                .labelStyle(TintedIconLabelStyle(tint: Palette.coral))
        } header: {
            Text("What it will and won't do")
        }
        .font(Typo.callout)
    }

    private var pipelineSection: some View {
        Section {
            ForEach(TraceCard.livePipeline) { stage in
                LabeledContent {
                    Text(stage.endpoint).font(Typo.monoSmall)
                } label: {
                    VStack(alignment: .leading) {
                        Text(stage.name)
                        Text(stage.purpose).font(Typo.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: {
            Text("Pipeline · https://api.meta.ai/v1")
        }
    }

    private func testConnection() async {
        connection = .checking
        do {
            let models = try await MetaClient.shared.listModels()
            connection = .ok(models.count)
            Haptics.success()
        } catch {
            connection = .failed(error.localizedDescription)
            Haptics.error()
        }
    }
}
