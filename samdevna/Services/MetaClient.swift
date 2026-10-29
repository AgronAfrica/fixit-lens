import CoreGraphics
import Combine
import Foundation
import os

/// Meta Model API model IDs used by Fix-it Lens. Every model call in the app goes to
/// `https://api.meta.ai/v1` with one of these.
enum MetaModel {
    static let sam = "sam-3.1"
    static let transcribe = "muse-voice-transcribe-1.0"
    static let spark = "muse-spark-1.3"
    static let wonder = "muse-wonder-1.0"
    static let image = "muse-image-1.0"
}

struct MetaCall: Identifiable, Sendable {
    let id = UUID()
    let model: String
    let endpoint: String
    let status: Int
    let milliseconds: Int
    let purpose: String
    let attempt: Int

    var succeeded: Bool { (200..<300).contains(status) }

    var displayName: String {
        switch model {
        case MetaModel.sam: "SAM 3.1"
        case MetaModel.transcribe: "Muse Voice Transcribe"
        case MetaModel.spark: "Muse Spark 1.3"
        case MetaModel.wonder: "Muse Wonder 1.0"
        case MetaModel.image: "Muse Image 1.0"
        case "models": "Model list"
        default: model
        }
    }

    var glyph: String {
        switch model {
        case MetaModel.sam: "viewfinder"
        case MetaModel.transcribe: "waveform"
        case MetaModel.spark: "brain"
        case MetaModel.wonder: "checklist"
        case MetaModel.image: "photo.artframe"
        default: "network"
        }
    }

    var latency: String {
        milliseconds >= 1000 ? String(format: "%.1f s", Double(milliseconds) / 1000) : "\(milliseconds) ms"
    }

    var statusText: String {
        switch status {
        case -2: "cancelled"
        case -1: "offline"
        default: "\(status)"
        }
    }
}

/// Every Meta model call made during the current run, shown in the repair sheet.
@MainActor
final class MetaTrace: ObservableObject {
    static let shared = MetaTrace()
    @Published private(set) var calls: [MetaCall] = []

    func reset() { calls.removeAll() }
    func record(_ call: MetaCall) { calls.append(call) }
    var totalMilliseconds: Int { calls.reduce(0) { $0 + $1.milliseconds } }
}

/// A decoded `/v1/responses` body. Safe to pass across actors.
struct MetaResponse: @unchecked Sendable {
    // JSONSerialization output is immutable once built; never mutated after init.
    let json: [String: Any]

    /// Concatenated `output_text` / `output[].content[].text`.
    var text: String {
        if let text = json["output_text"] as? String, !text.isEmpty { return text }
        guard let output = json["output"] as? [[String: Any]] else { return "" }
        return output
            .compactMap { $0["content"] as? [[String: Any]] }
            .flatMap { $0 }
            .compactMap { $0["text"] as? String }
            .joined(separator: "\n")
    }

    /// Base64 PNG/JPEG from an `image_generation_call` output item.
    var imageData: Data? {
        guard let output = json["output"] as? [[String: Any]] else { return nil }
        for item in output where item["type"] as? String == "image_generation_call" {
            if let b64 = item["result"] as? String, let data = Data(base64Encoded: b64) { return data }
        }
        return nil
    }
}

/// The single gateway to Meta's Model API. Handles auth, retries with backoff
/// (429 / 5xx / timeouts, honouring `Retry-After`), cancellation and the call trace.
actor MetaClient {
    static let shared = MetaClient()

    private let log = Logger(subsystem: "com.codewithik.samdevna", category: "MetaAPI")
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 240
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()
    private let maxAttempts = 3

    // MARK: Endpoints

    /// `POST /v1/responses` — SAM 3.1, Muse Spark, Muse Wonder and Muse Image.
    func responses(model: String, purpose: String, body: [String: Any]) async throws -> MetaResponse {
        var payload = body
        payload["model"] = model
        payload["store"] = false
        let bodyData = try JSONSerialization.data(withJSONObject: payload)
        let data = try await send(
            path: "responses", method: "POST", contentType: "application/json", body: bodyData,
            model: model, endpoint: "POST /v1/responses", purpose: purpose
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FixError.http(200, "Unreadable response")
        }
        if let error = json["error"] as? [String: Any] {
            throw FixError.http(400, error["message"] as? String ?? "Unknown error")
        }
        return MetaResponse(json: json)
    }

    /// `POST /v1/asr/transcribe` — Muse Voice Transcribe, push-to-talk, mono 16-bit PCM WAV.
    func transcribeWAV(_ wav: Data, languageBias: [String], keywords: [String], purpose: String) async throws -> String {
        let boundary = "FixitLens-\(UUID().uuidString)"
        let settings = try JSONSerialization.data(withJSONObject: [
            "mode": "PUSH_TO_TALK",
            "model": MetaModel.transcribe,
            "audioEncoding": "WAV",
            "languageBias": languageBias,
            "keywords": keywords,
        ] as [String: Any])

        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"request\"\r\nContent-Type: application/json\r\n\r\n".utf8))
        body.append(settings)
        body.append(Data("\r\n--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"utterance.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let data = try await send(
            path: "asr/transcribe", method: "POST", contentType: "multipart/form-data; boundary=\(boundary)", body: body,
            model: MetaModel.transcribe, endpoint: "POST /v1/asr/transcribe", purpose: purpose
        )
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["transcript"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `GET /v1/models` — used by Settings › Test connection.
    func listModels() async throws -> [String] {
        let data = try await send(
            path: "models", method: "GET", contentType: nil, body: nil,
            model: "models", endpoint: "GET /v1/models", purpose: "Test connection"
        )
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }
        return items.compactMap { $0["id"] as? String }.sorted()
    }

    // MARK: Transport

    private func send(
        path: String, method: String, contentType: String?, body: Data?,
        model: String, endpoint: String, purpose: String
    ) async throws -> Data {
        let key = SecretStore.metaAPIKey
        guard !key.isEmpty else { throw FixError.missingKey }

        var request = URLRequest(url: SecretStore.metaBaseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        request.httpBody = body

        var attempt = 1
        while true {
            try Task.checkCancellation()
            let started = Date()
            do {
                let (data, response) = try await session.data(for: request)
                let http = response as? HTTPURLResponse
                let status = http?.statusCode ?? 0
                await record(model: model, endpoint: endpoint, status: status, started: started, purpose: purpose, attempt: attempt)
                if (200..<300).contains(status) { return data }

                let retryable = status == 429 || (500...599).contains(status)
                if retryable, attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(backoff(attempt: attempt, retryAfter: http?.value(forHTTPHeaderField: "Retry-After"))))
                    attempt += 1
                    continue
                }
                throw FixError.http(status, Self.errorMessage(from: data))
            } catch let error as FixError {
                throw error
            } catch is CancellationError {
                await record(model: model, endpoint: endpoint, status: -2, started: started, purpose: purpose, attempt: attempt)
                throw CancellationError()
            } catch let error as URLError {
                if error.code == .cancelled {
                    await record(model: model, endpoint: endpoint, status: -2, started: started, purpose: purpose, attempt: attempt)
                    throw CancellationError()
                }
                await record(model: model, endpoint: endpoint, status: -1, started: started, purpose: purpose, attempt: attempt)
                let transient: Set<URLError.Code> = [.timedOut, .networkConnectionLost, .cannotConnectToHost, .dnsLookupFailed]
                if transient.contains(error.code), attempt < maxAttempts {
                    try await Task.sleep(for: .seconds(backoff(attempt: attempt, retryAfter: nil)))
                    attempt += 1
                    continue
                }
                throw FixError.network(error.localizedDescription)
            }
        }
    }

    private func backoff(attempt: Int, retryAfter: String?) -> Double {
        if let retryAfter, let seconds = Double(retryAfter) { return min(seconds, 8) }
        return min(pow(2, Double(attempt - 1)) * 0.8 + Double.random(in: 0...0.3), 6)
    }

    /// Pulls `error.message` out of an OpenAI-style error envelope, else a short body prefix.
    private static func errorMessage(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let error = json["error"] as? [String: Any], let message = error["message"] as? String { return message }
            if let message = json["message"] as? String { return message }
        }
        return String(decoding: data.prefix(300), as: UTF8.self)
    }

    private func record(model: String, endpoint: String, status: Int, started: Date, purpose: String, attempt: Int) async {
        let call = MetaCall(
            model: model, endpoint: endpoint, status: status,
            milliseconds: Int(Date().timeIntervalSince(started) * 1000),
            purpose: purpose, attempt: attempt
        )
        log.info("\(model, privacy: .public) \(endpoint, privacy: .public) -> \(status) in \(call.milliseconds) ms (attempt \(attempt))")
        await MetaTrace.shared.record(call)
    }
}
