import Foundation

enum Paths {
    static let appSupport = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Phantom", isDirectory: true)

    static var venvPython: URL { appSupport.appendingPathComponent("venv/bin/python") }
    static var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: venvPython.path) }

    static var helperScript: URL? { resource("phantom_helper.py", devSubdirectory: "helper") }
    static var bootstrapScript: URL? { resource("bootstrap.sh", devSubdirectory: "scripts") }

    /// Bundled resources live in Contents/Resources; `PHANTOM_ROOT` points at a checkout for `swift run`.
    private static func resource(_ name: String, devSubdirectory: String) -> URL? {
        var candidates: [URL] = []
        if let root = ProcessInfo.processInfo.environment["PHANTOM_ROOT"] {
            candidates.append(URL(fileURLWithPath: root).appendingPathComponent(devSubdirectory).appendingPathComponent(name))
        }
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent(name))
        }
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}

/// Runs the bundled bootstrap script that installs pymobiledevice3 into Application Support.
@MainActor
final class Installer: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var output = ""
    @Published private(set) var didFail = false

    func install() async -> Bool {
        guard !isRunning else { return false }
        guard let script = Paths.bootstrapScript else {
            output = "bootstrap.sh is missing from the app bundle. Rebuild with scripts/build.sh."
            didFail = true
            return false
        }
        isRunning = true
        didFail = false
        output = ""

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [script.path]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let text = String(decoding: data, as: UTF8.self)
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.output += text } }
        }

        let status: Int32 = await withCheckedContinuation { continuation in
            proc.terminationHandler = { finished in continuation.resume(returning: finished.terminationStatus) }
            do {
                try proc.run()
            } catch {
                proc.terminationHandler = nil
                output += "Couldn't run the installer: \(error.localizedDescription)\n"
                continuation.resume(returning: -1)
            }
        }

        isRunning = false
        didFail = status != 0
        return status == 0
    }
}
