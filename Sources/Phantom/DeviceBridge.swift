import CoreLocation
import Foundation

/// Owns the Python helper process (pymobiledevice3) and mirrors device state for the UI.
///
/// The helper speaks newline-delimited JSON: requests go to its stdin, replies and events
/// come back on stdout, and its logging arrives on stderr.
@MainActor
final class DeviceBridge: ObservableObject {
    enum HelperState: Equatable {
        case stopped
        case notInstalled
        case starting
        case running
        case failed(String)
    }

    @Published private(set) var helperState: HelperState = .stopped
    @Published private(set) var devices: [DeviceInfo] = []
    @Published var selectedUDID: String?
    @Published private(set) var statuses: [String: SessionStatus] = [:]
    @Published var lastError: HelperFailure?
    @Published private(set) var log: [String] = []
    @Published private(set) var isRestoring = false
    @Published private(set) var restoreNotice: RestoreNotice?

    enum RestoreNotice {
        case restoring
        case restored
        case restoredWithoutMacLocation
    }

    private let macLocation = MacLocation()

    private var process: Process?
    private var helperInput: FileHandle?
    private var nextID = 1
    private var pending: [Int: CheckedContinuation<HelperMessage, Never>] = [:]
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var shuttingDown = false
    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
    private let timestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    var selectedDevice: DeviceInfo? { devices.first { $0.udid == selectedUDID } }
    var selectedStatus: SessionStatus? { selectedUDID.flatMap { statuses[$0] } }
    var canTeleport: Bool { helperState == .running && selectedDevice != nil }

    /// The coordinate currently simulated on the selected device, if any.
    var activeCoordinate: CLLocationCoordinate2D? {
        guard let status = selectedStatus,
              status.phase == .active || status.phase == .reconnecting,
              let latitude = status.latitude, let longitude = status.longitude
        else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // MARK: - Helper lifecycle

    func start() {
        guard process == nil else { return }
        guard Paths.isInstalled else {
            helperState = .notInstalled
            return
        }
        guard let script = Paths.helperScript else {
            helperState = .failed("phantom_helper.py is missing from the app bundle. Rebuild with scripts/build.sh.")
            return
        }

        let proc = Process()
        proc.executableURL = Paths.venvPython
        proc.arguments = ["-u", script.path]
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        proc.environment = environment

        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        proc.standardInput = input
        proc.standardOutput = output
        proc.standardError = errors

        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consumeStdout(data) } }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { handle.readabilityHandler = nil }
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.consumeStderr(data) } }
        }
        proc.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.helperExited(finished, status: status) }
            }
        }

        do {
            try proc.run()
        } catch {
            helperState = .failed("Couldn't launch the device helper: \(error.localizedDescription)")
            return
        }
        process = proc
        helperInput = input.fileHandleForWriting
        shuttingDown = false
        helperState = .starting
        appendLog("Helper started (pid \(proc.processIdentifier))")

        Task {
            let reply = await send(["cmd": "hello"])
            guard helperState == .starting else { return }
            if reply.ok == true {
                helperState = .running
            } else if reply.error?.code == "MISSING_DEPENDENCY" {
                helperState = .notInstalled
            } else {
                helperState = .failed(reply.error?.message ?? "The device helper didn't respond.")
            }
        }
    }

    func restart() {
        stop()
        start()
    }

    func stop() {
        guard let proc = process else { return }
        shuttingDown = true
        if proc.isRunning { proc.terminate() }
        cleanUpAfterExit(note: "Helper stopped")
    }

    /// Asks the helper to restore real locations and exit. Blocks briefly; used when the app quits.
    func shutdownAndWait(timeout: TimeInterval = 4) {
        guard let proc = process, proc.isRunning else { return }
        shuttingDown = true
        try? helperInput?.write(contentsOf: Data("{\"cmd\": \"shutdown\"}\n".utf8))
        let deadline = Date().addingTimeInterval(timeout)
        while proc.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if proc.isRunning { proc.terminate() }
    }

    private func helperExited(_ proc: Process, status: Int32) {
        guard proc === process else { return }
        let expected = shuttingDown
        cleanUpAfterExit(note: "Helper exited with status \(status)")
        if !expected, helperState == .stopped {
            helperState = .failed("The device helper stopped unexpectedly (status \(status)). Open Activity for details.")
        }
    }

    private func cleanUpAfterExit(note: String) {
        process = nil
        helperInput = nil
        stdoutBuffer.removeAll()
        stderrBuffer.removeAll()
        let waiting = pending
        pending.removeAll()
        for continuation in waiting.values {
            continuation.resume(returning: .failure("HELPER_DOWN", "The device helper isn't running."))
        }
        statuses.removeAll()
        devices.removeAll()
        appendLog(note)
        if helperState == .running || helperState == .starting {
            helperState = .stopped
        }
    }

    // MARK: - Commands

    /// Moves the selected device to `coordinate`. Returns true once the location is applied.
    func teleport(to coordinate: CLLocationCoordinate2D) async -> Bool {
        guard let udid = selectedUDID else {
            lastError = HelperFailure(code: "NO_DEVICE", message: "No device is selected.")
            return false
        }
        macLocation.prepare()  // restoring later uses this Mac's location; ask while the context is clear
        let reply = await send(["cmd": "set", "udid": udid, "lat": coordinate.latitude, "lon": coordinate.longitude])
        return report(reply) && reply.superseded != true
    }

    /// Clearing can take a few seconds (it may have to reconnect first), so a notice covers the wait.
    func restoreRealLocation() async {
        guard let udid = selectedUDID else { return }
        isRestoring = true
        restoreNotice = .restoring
        var request: [String: Any] = ["cmd": "clear", "udid": udid]
        // The device is next to this Mac, so the Mac's position stands in for its real one. The helper
        // settles the device there before stopping the simulation; see Session.clear for why.
        let here = await macLocation.current()
        if let here {
            request["anchor_lat"] = here.coordinate.latitude
            request["anchor_lon"] = here.coordinate.longitude
        } else {
            appendLog("This Mac's location isn't available, so restoring without it. After a far-away location the device may keep showing it until restarted.")
        }
        let restored = report(await send(request))
        isRestoring = false
        guard restored else {
            restoreNotice = nil  // the error banner takes over
            return
        }
        let notice: RestoreNotice = here == nil ? .restoredWithoutMacLocation : .restored
        restoreNotice = notice
        try? await Task.sleep(for: .seconds(here == nil ? 8 : 2.5))
        if restoreNotice == notice { restoreNotice = nil }
    }

    func pair() async {
        guard let udid = selectedUDID else { return }
        report(await send(["cmd": "pair", "udid": udid]))
    }

    func refreshDevices() async {
        report(await send(["cmd": "list"]))
    }

    @discardableResult
    private func report(_ reply: HelperMessage) -> Bool {
        if reply.ok == true {
            lastError = nil
            return true
        }
        lastError = reply.error ?? HelperFailure(code: "UNKNOWN", message: "The helper returned an empty reply.")
        return false
    }

    @discardableResult
    func send(_ payload: [String: Any]) async -> HelperMessage {
        guard let input = helperInput, process?.isRunning == true else {
            return .failure("HELPER_DOWN", "The device helper isn't running.")
        }
        let id = nextID
        nextID += 1
        var body = payload
        body["id"] = id
        guard var line = try? JSONSerialization.data(withJSONObject: body) else {
            return .failure("BAD_REQUEST", "Couldn't encode the request.")
        }
        line.append(0x0A)

        return await withCheckedContinuation { continuation in
            pending[id] = continuation
            do {
                try input.write(contentsOf: line)
            } catch {
                pending.removeValue(forKey: id)?
                    .resume(returning: .failure("HELPER_DOWN", "Couldn't reach the device helper: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Helper output

    private func consumeStdout(_ data: Data) {
        stdoutBuffer.append(data)
        while let newline = stdoutBuffer.firstIndex(of: 0x0A) {
            let line = Data(stdoutBuffer[stdoutBuffer.startIndex..<newline])
            stdoutBuffer.removeSubrange(stdoutBuffer.startIndex...newline)
            guard !line.isEmpty else { continue }
            do {
                dispatch(try decoder.decode(HelperMessage.self, from: line))
            } catch {
                appendLog("Unreadable helper output: \(String(decoding: line, as: UTF8.self))")
            }
        }
    }

    private func consumeStderr(_ data: Data) {
        stderrBuffer.append(data)
        while let newline = stderrBuffer.firstIndex(of: 0x0A) {
            let line = String(decoding: stderrBuffer[stderrBuffer.startIndex..<newline], as: UTF8.self)
            stderrBuffer.removeSubrange(stderrBuffer.startIndex...newline)
            if !line.trimmingCharacters(in: .whitespaces).isEmpty { appendLog(line) }
        }
    }

    private func dispatch(_ message: HelperMessage) {
        if let devices = message.devices { apply(devices) }
        if let status = message.status { statuses[status.udid] = status }

        if let id = message.id, let continuation = pending.removeValue(forKey: id) {
            continuation.resume(returning: message)
            return
        }

        switch message.event {
        case "log":
            if let text = message.message { appendLog(text) }
        case "fatal":
            let failure = message.error ?? HelperFailure(code: "UNKNOWN", message: "The helper failed to start.")
            appendLog("Helper error: \(failure.message)")
            helperState = failure.code == "MISSING_DEPENDENCY" ? .notInstalled : .failed(failure.message)
        default:
            break
        }
    }

    private func apply(_ list: [DeviceInfo]) {
        devices = list
        if let selected = selectedUDID, list.contains(where: { $0.udid == selected }) { return }
        selectedUDID = list.first(where: { $0.connection == "USB" })?.udid ?? list.first?.udid
    }

    private func appendLog(_ line: String) {
        log.append("\(timestamp.string(from: Date()))  \(line)")
        if log.count > 500 { log.removeFirst(log.count - 500) }
    }
}
