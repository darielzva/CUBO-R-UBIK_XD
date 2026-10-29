import Foundation
import AVFAudio
import Network
import UserNotifications
import AirliftFFI

@MainActor
final class PairingController: NSObject, ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var status = "idle"
    @Published private(set) var pin: String?
    @Published private(set) var errorMessage: String?

    private let hostName = "Raki"
    private let hostModel = "iPhone"
    private let localNetworkAuthorization = PairingLocalNetworkAuthorization()
    private let keepAlive = PairingKeepAlive()
    private var netService: NetService?
    private var continuation: CheckedContinuation<URL, Error>?
    private var pinNotificationTitle = "Pairing PIN"
    private var pinNotificationBodyFormat = "Pairing PIN: %@"
    private static var airliftLoggerInstalled = false

    nonisolated static var pairingFileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("aircard_pairing.plist")
    }

    static func removeLegacyTransportLogs() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        for name in ["airlift_transport_log", "airlift_transport_log.txt", "airlift_transport_log.log"] {
            try? FileManager.default.removeItem(at: documents.appendingPathComponent(name))
        }
    }

    enum PairingError: LocalizedError {
        case alreadyRunning
        case failed(String)
        case emptyFile

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "Pairing is already running."
            case .failed(let message):
                return message
            case .emptyFile:
                return "Pairing completed without creating a pairing file."
            }
        }
    }

    func start(pinNotificationTitle: String, pinNotificationBodyFormat: String) {
        guard !isRunning else {
            errorMessage = PairingError.alreadyRunning.localizedDescription
            return
        }
        isRunning = true
        pin = nil
        errorMessage = nil
        self.pinNotificationTitle = pinNotificationTitle
        self.pinNotificationBodyFormat = pinNotificationBodyFormat
        status = "Starting pairing host…"
        Self.removeLegacyTransportLogs()
        installAirliftLogger()
        log("pairing: direct pairing host requested")

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
            await self.requestPinNotifications()
                await self.localNetworkAuthorization.request()
                guard self.isRunning else { return }
                self.keepAlive.start()
                self.status = "Waiting for Developer Mode pairing…"
                _ = try await self.runPairing()
            } catch is CancellationError {
                self.status = "Cancelled"
            } catch {
                self.errorMessage = error.localizedDescription
                self.status = "Pairing failed"
            }
            self.isRunning = false
            self.stopAdvertising()
            self.localNetworkAuthorization.stop()
            self.stopKeepAliveAfterReturn()
            Self.removeLegacyTransportLogs()
        }
    }

    func cancel() {
        stopAdvertising()
        localNetworkAuthorization.stop()
        keepAlive.stop()
        isRunning = false
        pin = nil
        status = "Cancelled"
        continuation?.resume(throwing: CancellationError())
        continuation = nil
        Self.removeLegacyTransportLogs()
    }

    private func runPairing() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                self.continuation = continuation
                self.runHost()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    private func runHost() {
        let outputPath = Self.pairingFileURL.path
        let name = hostName
        let model = hostModel
        let context = Unmanaged.passRetained(self).toOpaque()

        DispatchQueue.global(qos: .userInitiated).async {
            var result = ALPairResult()
            let returnCode = name.withCString { namePointer in
                model.withCString { modelPointer in
                    outputPath.withCString { pathPointer in
                        "".withCString { irkPointer in
                            al_pairing_run_host(
                                "0.0.0.0",
                                0,
                                namePointer,
                                modelPointer,
                                pathPointer,
                                irkPointer,
                                pairingReadyCallback,
                                pairingPinCallback,
                                context,
                                &result
                            )
                        }
                    }
                }
            }

            let error = returnCode == 0 ? nil : Self.copyCString(result.error)
            let output = URL(fileURLWithPath: outputPath)
            let fileIsReady = (try? Data(contentsOf: output).isEmpty == false) ?? false
            al_pairing_result_free(&result)

            DispatchQueue.main.async {
                let controller = Unmanaged<PairingController>.fromOpaque(context).takeUnretainedValue()
                Unmanaged<PairingController>.fromOpaque(context).release()
                guard controller.isRunning else { return }
                if let error {
                    log("pairing: host failed: \(error)")
                    controller.finish(.failure(PairingError.failed(error)))
                } else if returnCode != 0 || !fileIsReady {
                    controller.finish(.failure(PairingError.emptyFile))
                } else {
                    controller.finish(.success(output))
                }
            }
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        stopAdvertising()
        isRunning = false
        pin = nil
        continuation?.resume(with: result)
        continuation = nil
        if case .success = result {
            status = "Pairing ready"
        }
        stopKeepAliveAfterReturn()
    }

    private func stopKeepAliveAfterReturn() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.keepAlive.stop()
        }
    }

    private func startAdvertising(serviceID: String, port: UInt16, values: [String: Data]) {
        stopAdvertising()
        let service = NetService(
            domain: "local.",
            type: "_remotepairing-pairable-host._tcp.",
            name: serviceID,
            port: Int32(port)
        )
        service.setTXTRecord(NetService.data(fromTXTRecord: values))
        service.publish()
        netService = service
        status = "Open Settings > Privacy & Security > Developer Mode to pair."
        log("pairing: Bonjour service \(serviceID) published on port \(port)")
    }

    private func stopAdvertising() {
        netService?.stop()
        netService = nil
    }

    private func installAirliftLogger() {
        guard !Self.airliftLoggerInstalled else { return }
        let result = al_log_init(airliftLogCallback, nil)
        guard result == 0 || result == 1 else {
            log("pairing: Airlift logger initialization failed (\(result))")
            return
        }
        Self.airliftLoggerInstalled = true
    }

    private func requestPinNotifications() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            log("pairing: notification permission request failed: \(error.localizedDescription)")
        }
    }

    private func notifyPairingPin(_ value: String) {
        let content = UNMutableNotificationContent()
        content.title = pinNotificationTitle
        content.body = String(format: pinNotificationBodyFormat, value)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: "pairing-pin-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                log("pairing: could not schedule PIN notification: \(error.localizedDescription)")
            }
        }
    }

    nonisolated private static func copyCString(_ pointer: UnsafeMutablePointer<CChar>?) -> String? {
        guard let pointer else { return nil }
        return String(cString: pointer)
    }

    fileprivate func handleReady(serviceID: String, port: UInt16, values: [String: Data]) {
        startAdvertising(serviceID: serviceID, port: port, values: values)
    }

    fileprivate func handlePin(_ value: String) {
        pin = value
        status = "Enter PIN \(value) in Developer Mode."
        log("pairing: PIN received; notification scheduled")
        notifyPairingPin(value)
    }
}

private let airliftLogCallback: ALLogCallback = { _, message in
    guard let message else { return }
    let line = String(cString: message).trimmingCharacters(in: .whitespacesAndNewlines)
    guard !line.isEmpty else { return }
    log("Airlift: \(line)")
}

@MainActor
private final class PairingLocalNetworkAuthorization {
    private var listener: NWListener?
    private var browser: NWBrowser?

    func request() async {
        let parameters = NWParameters.tcp
        parameters.includePeerToPeer = true

        let listener = try? NWListener(using: parameters)
        listener?.service = NWListener.Service(name: "RakiProbe", type: "_aircardprobe._tcp")
        listener?.newConnectionHandler = { $0.cancel() }
        self.listener = listener

        let browser = NWBrowser(for: .bonjour(type: "_aircardprobe._tcp", domain: nil), using: parameters)
        self.browser = browser
        listener?.start(queue: .main)
        browser.start(queue: .main)
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        stop()
    }

    func stop() {
        browser?.cancel()
        browser = nil
        listener?.cancel()
        listener = nil
    }
}

@MainActor
private final class PairingKeepAlive {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var isPlaying = false

    func start() {
        guard !isPlaying else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)

            if player.engine == nil {
                engine.attach(player)
            }
            let format = engine.outputNode.inputFormat(forBus: 0)
            guard format.sampleRate > 0, format.channelCount > 0 else {
                isPlaying = true
                return
            }
            engine.connect(player, to: engine.mainMixerNode, format: format)

            let frames = max(1024, AVAudioFrameCount(format.sampleRate))
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return }
            buffer.frameLength = frames
            if let channelData = buffer.floatChannelData {
                for channel in 0..<Int(format.channelCount) {
                    memset(channelData[channel], 0, Int(frames) * MemoryLayout<Float>.size)
                }
            }
            if !engine.isRunning {
                try engine.start()
            }
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
            isPlaying = true
        } catch {
            isPlaying = false
        }
    }

    func stop() {
        guard isPlaying else { return }
        isPlaying = false
        player.stop()
        if engine.isRunning {
            engine.stop()
        }
        if player.engine != nil {
            engine.detach(player)
        }
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }
}

private let pairingReadyCallback: ALPairReadyCb = { context, serviceID, port, keys, values, count in
    guard let context, let serviceID else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(context).takeUnretainedValue()
    let copiedServiceID = String(cString: serviceID)
    var records: [String: Data] = [:]
    if let keys, let values {
        for index in 0..<Int(count) {
            guard let key = keys[index], let value = values[index] else { continue }
            records[String(cString: key)] = Data(String(cString: value).utf8)
        }
    }
    DispatchQueue.main.async {
        controller.handleReady(serviceID: copiedServiceID, port: port, values: records)
    }
}

private let pairingPinCallback: ALPairPinCb = { pin, context in
    guard let pin, let context else { return }
    let controller = Unmanaged<PairingController>.fromOpaque(context).takeUnretainedValue()
    let copiedPin = String(cString: pin)
    DispatchQueue.main.async {
        controller.handlePin(copiedPin)
    }
}
