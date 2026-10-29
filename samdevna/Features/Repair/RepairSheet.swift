import CoreGraphics
import SwiftUI

/// The repair plan: fault, hazard, steps, tools, illustration and the Meta call trace.
struct RepairSheet: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                if let plan = model.plan {
                    VStack(alignment: .leading, spacing: Space.l) {
                        header(plan)
                        if plan.hazard == .stop {
                            SafetyStopCard(reason: plan.hazardReason)
                        } else {
                            if plan.hazard == .caution, !plan.hazardReason.isEmpty {
                                CautionCard(text: plan.hazardReason)
                            }
                            startButton(plan)
                            diagnosis(plan)
                            StepsList(steps: Array(plan.steps.prefix(plan.isDemo ? plan.steps.count : max(model.revealedSteps, 0))), total: plan.steps.count)
                            needs(plan)
                            IllustrationCard()
                        }
                        if !model.progress.isEmpty { PipelineTimeline(items: model.progress) }
                        TraceCard()
                        footnote(plan)
                    }
                    .padding(Space.m)
                    .padding(.bottom, Space.xl)
                } else {
                    EmptyStateView(
                        glyph: "wrench.and.screwdriver",
                        title: "No plan yet",
                        message: "Tap the broken part on the photo, or hold the mic and describe it."
                    )
                }
            }
            .background(Palette.canvas)
            .scrollIndicators(.hidden)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if let plan = model.plan {
                        ShareLink(item: plan.shareText) { Image(systemName: "square.and.arrow.up") }
                            .accessibilityLabel("Share the plan")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { model.showPlan = false }
                        .font(Typo.headline)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: Sections

    private func header(_ plan: RepairPlan) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(spacing: Space.xs) {
                Pill(title: plan.hazard.title, glyph: plan.hazard.glyph, tint: plan.hazard.tint, filled: plan.hazard == .stop)
                    .accessibilityIdentifier("plan.hazard")
                if plan.hazard != .stop {
                    if !plan.difficulty.isEmpty { Pill(title: plan.difficulty.capitalized, glyph: "gauge.with.dots.needle.33percent", tint: Palette.sky) }
                    if plan.minutes > 0 { Pill(title: "\(plan.minutes) min", glyph: "clock", tint: Palette.textSecondary) }
                }
                Spacer(minLength: 0)
                if plan.confidence > 0 { ConfidenceMeter(value: plan.confidence) }
            }
            Text(plan.objectName)
                .font(Typo.footnote)
                .foregroundStyle(Palette.textSecondary)
                .textCase(.uppercase)
                .tracking(1)
            Text(plan.fault)
                .font(Typo.display)
                .foregroundStyle(Palette.text)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("plan.fault")
            ReviewBadge(state: model.review)
        }
        .accessibilityElement(children: .contain)
    }

    private func startButton(_ plan: RepairPlan) -> some View {
        Button {
            Haptics.success()
            model.startGuide()
        } label: {
            Label(model.handsFree && !model.isReplay ? "Start hands-free guide" : "Start step-by-step guide",
                  systemImage: "waveform.and.mic")
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(plan.steps.isEmpty)
        .accessibilityIdentifier("plan.startGuide")
    }

    private func diagnosis(_ plan: RepairPlan) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("What's wrong", glyph: "magnifyingglass")
            if !plan.faultDetail.isEmpty {
                Text(plan.faultDetail).font(Typo.body).foregroundStyle(Palette.text)
            }
            if !plan.likelyCause.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text("Likely cause").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    Text(plan.likelyCause).font(Typo.callout).foregroundStyle(Palette.text)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    @ViewBuilder
    private func needs(_ plan: RepairPlan) -> some View {
        if !plan.tools.isEmpty || !plan.parts.isEmpty || !plan.avoid.isEmpty {
            VStack(alignment: .leading, spacing: Space.s) {
                if !plan.tools.isEmpty {
                    SectionLabel("You'll need", glyph: "wrench.adjustable")
                    FlowLayout(spacing: 6) {
                        ForEach(plan.tools + plan.parts, id: \.self) { item in
                            Pill(title: item, tint: Palette.text)
                        }
                    }
                }
                if !plan.avoid.isEmpty {
                    SectionLabel("Don't", glyph: "xmark.octagon", tint: Palette.coral)
                        .padding(.top, Space.xs)
                    ForEach(plan.avoid, id: \.self) { item in
                        Label(item, systemImage: "xmark")
                            .font(Typo.callout)
                            .foregroundStyle(Palette.text)
                            .labelStyle(TintedIconLabelStyle(tint: Palette.coral))
                    }
                }
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()
        }
    }

    private func footnote(_ plan: RepairPlan) -> some View {
        Text(plan.isDemo
             ? "Demo replay: this plan and its highlights are scripted. Add a Meta API key and turn off demo replay to run it live."
             : "Generated by Meta models from your photo. Check your manual, and stop if anything feels unsafe.")
            .font(Typo.caption)
            .foregroundStyle(Palette.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Cards

struct SafetyStopCard: View {
    let reason: String

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Label("Stop. Call a professional.", systemImage: "hand.raised.fill")
                .font(Typo.title3)
                .foregroundStyle(Palette.coral)
            Text(reason.isEmpty ? "This job isn't safe to do yourself." : reason)
                .font(Typo.body)
                .foregroundStyle(Palette.text)
            Text("Fix-it Lens won't guide gas, mains electrics, refrigerant, airbags, fuel leaks or structural work.")
                .font(Typo.footnote)
                .foregroundStyle(Palette.textSecondary)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(fill: Palette.coral.opacity(0.12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("plan.safetyStop")
    }
}

private struct CautionCard: View {
    let text: String

    var body: some View {
        Label(text, systemImage: "exclamationmark.triangle.fill")
            .font(Typo.callout)
            .foregroundStyle(Palette.text)
            .labelStyle(TintedIconLabelStyle(tint: Palette.saffron))
            .padding(Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(fill: Palette.saffron.opacity(0.12))
    }
}

private struct StepsList: View {
    let steps: [RepairStep]
    var total: Int? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("\(total ?? steps.count) steps", glyph: "list.number")
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: Space.s) {
                    Text("\(index + 1)")
                        .font(Typo.headline)
                        .monospacedDigit()
                        .foregroundStyle(Palette.onAmber)
                        .frame(width: 30, height: 30)
                        .background(Palette.amber, in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(step.title).font(Typo.headline).foregroundStyle(Palette.text)
                        Text(step.instruction).font(Typo.callout).foregroundStyle(Palette.textSecondary)
                        HStack(spacing: 6) {
                            if !step.part.isEmpty { Pill(title: step.part, glyph: "viewfinder", tint: Palette.amber) }
                            if !step.tool.isEmpty { Pill(title: step.tool, glyph: "wrench.adjustable", tint: Palette.sky) }
                        }
                        if !step.caution.isEmpty {
                            Label(step.caution, systemImage: "exclamationmark.triangle.fill")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.saffron)
                        }
                    }
                }
                .padding(Space.s)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(Radius.s)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

private struct IllustrationCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel("Visual guide · Muse Image", glyph: "photo.artframe")
            switch model.illustrationState {
            case .ready:
                if let image = model.illustration {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
                        .accessibilityLabel("Illustrated repair guide")
                        .accessibilityIdentifier("plan.illustration")
                }
            case .drawing:
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Palette.elevated)
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        VStack(spacing: Space.xs) {
                            ProgressView()
                            Text("Drawing an exploded view of the fix…")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .shimmering()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
            case .failed:
                Text("The illustration didn't come through. The steps above are all you need.")
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
            case .none:
                Text(model.isReplay
                     ? "In live mode, Muse Image 1.0 draws an exploded-view guide of this exact fix."
                     : "No illustration for this plan.")
                    .font(Typo.callout)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Every Meta Model API call in this run, with endpoint, status and latency.
struct TraceCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(model.isReplay ? "Live pipeline (not called in replay)" : "Meta API calls", glyph: "point.3.connected.trianglepath.dotted")
            if model.isReplay {
                ForEach(Self.livePipeline) { stage in
                    row(glyph: "circle.dashed", name: stage.name, detail: "\(stage.endpoint) · \(stage.purpose)", trailing: "", ok: nil)
                }
            } else if model.trace.calls.isEmpty {
                Text("No calls yet.").font(Typo.callout).foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(model.trace.calls) { call in
                    row(glyph: call.glyph, name: call.displayName,
                        detail: "\(call.endpoint) · \(call.purpose)\(call.attempt > 1 ? " · retry \(call.attempt - 1)" : "")",
                        trailing: "\(call.statusText) · \(call.latency)", ok: call.succeeded)
                        .accessibilityIdentifier("trace.\(call.model).\(call.succeeded ? "ok" : "failed")")
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    struct LiveStage: Identifiable {
        let name: String
        let endpoint: String
        let purpose: String
        var id: String { name }
    }

    static let livePipeline: [LiveStage] = [
        LiveStage(name: "Muse Voice Transcribe", endpoint: "POST /v1/asr/transcribe", purpose: "hears you"),
        LiveStage(name: "SAM 3.1", endpoint: "POST /v1/responses", purpose: "outlines the exact part"),
        LiveStage(name: "Muse Spark 1.3", endpoint: "POST /v1/responses", purpose: "finds the fault, answers questions"),
        LiveStage(name: "Muse Wonder 1.0", endpoint: "POST /v1/responses", purpose: "reviews the plan for safety"),
        LiveStage(name: "Muse Image 1.0", endpoint: "POST /v1/responses", purpose: "draws the fix"),
    ]

    private func row(glyph: String, name: String, detail: String, trailing: String, ok: Bool?) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: glyph)
                .frame(width: 28, height: 28)
                .foregroundStyle(ok == false ? Palette.coral : Palette.amber)
                .background(Palette.elevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(Typo.subheadline).foregroundStyle(Palette.text)
                Text(detail).font(Typo.monoSmall).foregroundStyle(Palette.textSecondary).lineLimit(2)
            }
            Spacer(minLength: 0)
            if !trailing.isEmpty {
                Text(trailing)
                    .font(Typo.monoSmall)
                    .foregroundStyle(ok == false ? Palette.coral : Palette.teal)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct TintedIconLabelStyle: LabelStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
            configuration.icon.foregroundStyle(tint)
            configuration.title
        }
    }
}


/// "Safety check running · Muse Wonder" while the background review runs, then its outcome.
struct ReviewBadge: View {
    let state: ReviewState

    var body: some View {
        if state != .idle {
            Label(state.label, systemImage: glyph)
                .font(Typo.caption)
                .foregroundStyle(tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(tint.opacity(0.12), in: Capsule())
                .modifier(ShimmerIf(active: state == .running))
                .accessibilityIdentifier("plan.review")
                .transition(.opacity)
        }
    }

    private var glyph: String {
        switch state {
        case .running: "shield.lefthalf.filled"
        case .stopped: "hand.raised.fill"
        case .failed: "shield.slash"
        case .raised, .overruled: "exclamationmark.shield"
        default: "checkmark.shield.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .stopped: Palette.coral
        case .raised, .overruled, .failed: Palette.amber
        case .running: Palette.sky
        default: Palette.teal
        }
    }
}

private struct ShimmerIf: ViewModifier {
    let active: Bool
    func body(content: Content) -> some View {
        if active { content.shimmering() } else { content }
    }
}

/// Live timeline of the parallel pipeline: which Meta model is doing what, with real elapsed times.
struct PipelineTimeline: View {
    let items: [ProgressItem]

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            VStack(alignment: .leading, spacing: Space.xs) {
                SectionLabel("Pipeline", glyph: "point.3.connected.trianglepath.dotted")
                ForEach(items) { item in
                    HStack(spacing: Space.xs) {
                        icon(item.status)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.model).font(Typo.monoSmall).foregroundStyle(Palette.amber)
                            Text(item.detail.isEmpty ? item.label : "\(item.label) · \(item.detail)")
                                .font(Typo.caption)
                                .foregroundStyle(Palette.text)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 0)
                        Text(String(format: "%.1fs", item.seconds ?? context.date.timeIntervalSince(item.started)))
                            .font(Typo.mono)
                            .monospacedDigit()
                            .foregroundStyle(item.finished == nil ? Palette.sky : Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        .accessibilityIdentifier("plan.timeline")
    }

    @ViewBuilder
    private func icon(_ status: ProgressItem.Status) -> some View {
        switch status {
        case .running: ProgressView().controlSize(.mini).tint(Palette.sky)
        case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.teal)
        case .skipped: Image(systemName: "minus.circle").foregroundStyle(Palette.textSecondary)
        case .failed: Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.amber)
        }
    }
}
