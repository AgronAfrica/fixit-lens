import CoreGraphics
import Foundation

/// The link to the relay. Live mode is a WebSocket (URLSessionWebSocketTask, no third-party code):
/// JPEG frames and WAV clips as binary `TogetherMedia`, everything else as JSON `TogetherMessage`.
/// If the socket can't be held open it drops to snapshot mode over plain HTTPS (POST a frame about
/// once a second, poll messages), and keeps retrying the socket with backoff.
@MainActor
final class TogetherTransport {
    enum Link: Equatable { case connecting, live, snapshot, closed(String) }

    var onMessage: ((TogetherMessage) -> Void)?
    var onMedia: ((TogetherMedia) -> Void)?
    var onLink: ((Link) -> Void)?

    private(set) var link: Link = .connecting { didSet { if link != oldValue { onLink?(link) } } }
    private let relay: URL
    private let code: String
    private let role: TogetherRole
    private let name: String
    private let language: String
    private let pollerID = String(UUID().uuidString.prefix(8))
    private let session: URLSession
    private var socket: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var retry = 0
    private var pollAfter = 0
    private var closed = false

    init(relay: URL, code: String, role: TogetherRole, name: String, language: String) {
        self.relay = relay
        self.code = code
        self.role = role
        self.name = name
        self.language = language
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    func connect() {
        closed = false
        openSocket()
    }

    func close() {
        closed = true
        receiveTask?.cancel(); pingTask?.cancel(); pollTask?.cancel()
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        link = .closed("Left the session")
    }

    // MARK: Send

    func send(_ message: TogetherMessage) {
        if link == .live, let socket {
            socket.send(.string(message.json())) { _ in }
        } else {
            post(path: "messages", body: Data(message.json().utf8), contentType: "application/json")
        }
    }

    /// Returns false when the frame wasn't sent (snapshot mode throttles itself to the poll rate).
    @discardableResult
    func send(_ media: TogetherMedia) -> Bool {
        if link == .live, let socket {
            socket.send(.data(media.encoded())) { _ in }
            return true
        }
        guard link == .snapshot else { return false }
        post(path: media.kind == .jpeg ? "snapshot" : "audio", body: media.encoded(), contentType: "application/octet-stream")
        return true
    }

    // MARK: Socket

    private func openSocket() {
        guard !closed else { return }
        link = link == .snapshot ? .snapshot : .connecting
        var components = URLComponents(url: relay, resolvingAgainstBaseURL: false)!
        components.scheme = relay.scheme == "http" ? "ws" : "wss"
        components.path = "/ws/\(code)"
        components.queryItems = [
            URLQueryItem(name: "role", value: role.rawValue),
            URLQueryItem(name: "name", value: name),
            URLQueryItem(name: "lang", value: language),
        ]
        guard let url = components.url else { return startPolling() }
        let task = session.webSocketTask(with: url)
        task.maximumMessageSize = 4 * 1024 * 1024
        socket = task
        task.resume()
        task.send(.string(TogetherMessage.hello(role: role, name: name, language: language, platform: "ios").json())) { _ in }
        receiveTask?.cancel()
        receiveTask = Task { [weak self] in await self?.receiveLoop(task) }
        pingTask?.cancel()
        pingTask = Task { [weak self] in await self?.pingLoop(task) }
        // If nothing confirms the socket in 6 s, help in snapshot mode meanwhile.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard let self, self.socket === task, self.link == .connecting else { return }
            self.startPolling()
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let message = try await task.receive()
                if link != .live {
                    link = .live
                    retry = 0
                    stopPolling()
                }
                switch message {
                case .string(let text):
                    if let parsed = TogetherMessage.parse(text) { onMessage?(parsed) }
                case .data(let data):
                    if let media = TogetherMedia(data) { onMedia?(media) }
                @unknown default:
                    break
                }
            } catch {
                guard socket === task else { return }
                socketDropped(task)
                return
            }
        }
    }

    private func pingLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(8))
            guard socket === task else { return }
            let alive = await withCheckedContinuation { continuation in
                task.sendPing { error in continuation.resume(returning: error == nil) }
            }
            if alive, link == .connecting { link = .live; stopPolling() }
            if !alive { socketDropped(task); return }
        }
    }

    private func socketDropped(_ task: URLSessionWebSocketTask) {
        if task.closeCode.rawValue == 4429 {
            link = .closed("Room is full (max \(Together.maxPeers))")
            closed = true
            return
        }
        task.cancel()
        socket = nil
        guard !closed else { return }
        startPolling()
        let wait = min(15.0, pow(2, Double(retry)))
        retry += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            self?.openSocket()
        }
    }

    // MARK: HTTP snapshot mode

    private func startPolling() {
        guard pollTask == nil, !closed else { return }
        link = .snapshot
        send(.hello(role: role, name: name, language: language, platform: "ios"))
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pollOnce()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func pollOnce() async {
        // A polling Fixer collects queued helper voice clips.
        if role == .fixer, let url = endpoint("audio"), let (data, response) = try? await session.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200, let media = TogetherMedia(data) {
            onMedia?(media)
        }
        // Helpers also fetch the latest frame; the Fixer only needs messages.
        if role == .helper, let url = endpoint("snapshot"), let (data, response) = try? await session.data(from: url),
           (response as? HTTPURLResponse)?.statusCode == 200 {
            let seq = UInt32((response as? HTTPURLResponse)?.value(forHTTPHeaderField: "X-Seq") ?? "") ?? 0
            onMedia?(TogetherMedia(kind: .jpeg, seq: seq, payload: data))
        }
        guard let url = endpoint("messages", extra: [URLQueryItem(name: "after", value: String(pollAfter))]),
              let (data, _) = try? await session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        pollAfter = (object["last"] as? Int) ?? pollAfter
        for raw in (object["messages"] as? [[String: Any]]) ?? [] {
            guard let json = try? JSONSerialization.data(withJSONObject: raw),
                  let parsed = TogetherMessage.parse(String(decoding: json, as: UTF8.self)) else { continue }
            onMessage?(parsed)
        }
    }

    private func post(path: String, body: Data, contentType: String) {
        guard let url = endpoint(path) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        session.dataTask(with: request).resume()
    }

    private func endpoint(_ path: String, extra: [URLQueryItem] = []) -> URL? {
        var components = URLComponents(url: relay, resolvingAgainstBaseURL: false)
        components?.path = "/api/rooms/\(code)/\(path)"
        components?.queryItems = [URLQueryItem(name: "role", value: role.rawValue), URLQueryItem(name: "pid", value: pollerID)] + extra
        return components?.url
    }
}
