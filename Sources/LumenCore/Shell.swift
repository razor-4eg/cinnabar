import Foundation
import os

final class FinishGate: @unchecked Sendable {
    private let lock = NSLock()
    private var closed = false

    var isClosed: Bool {
        lock.lock()
        defer { lock.unlock() }
        return closed
    }

    func once(_ body: () -> Void) {
        lock.lock()
        let shouldRun = !closed
        if shouldRun { closed = true }
        lock.unlock()
        if shouldRun { body() }
    }
}

final class LineProcess: @unchecked Sendable {
    private let process = Process()
    private let pipe = Pipe()
    private let gate = FinishGate()

    func stream(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL?
    ) -> AsyncThrowingStream<String, Error> {
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.qualityOfService = .userInitiated
        if let directory {
            process.currentDirectoryURL = directory
        }
        process.standardOutput = pipe
        process.standardError = pipe

        return AsyncThrowingStream { continuation in
            let handle = self.pipe.fileHandleForReading
            let buffer = OSAllocatedUnfairLock(initialState: Data())

            handle.readabilityHandler = { file in
                let chunk = file.availableData
                if chunk.isEmpty { return }
                let lines = buffer.withLock { data -> [String] in
                    data.append(chunk)
                    return Self.drain(&data)
                }
                guard !self.gate.isClosed else { return }
                for line in lines {
                    guard !self.gate.isClosed else { return }
                    continuation.yield(line)
                }
            }

            self.process.terminationHandler = { proc in
                let tail = buffer.withLock { data -> [String] in
                    let lines = Self.drain(&data)
                    if !data.isEmpty {
                        let rest = String(decoding: data, as: UTF8.self)
                        data.removeAll()
                        return lines + (rest.isEmpty ? [] : [rest])
                    }
                    return lines
                }
                for line in tail {
                    continuation.yield(line)
                }
                handle.readabilityHandler = nil
                self.gate.once {
                    if proc.terminationStatus == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: EngineFailure(message: "exit \(proc.terminationStatus)"))
                    }
                }
            }

            do {
                try self.process.run()
            } catch {
                self.gate.once {
                    continuation.finish(throwing: EngineFailure(message: String(format: String(localized: "Couldn't launch %@."), executable.lastPathComponent)))
                }
            }

            continuation.onTermination = { _ in
                if self.process.isRunning {
                    self.process.terminate()
                }
                handle.readabilityHandler = nil
            }
        }
    }

    private static func drain(_ data: inout Data) -> [String] {
        var lines: [String] = []
        while let index = data.firstIndex(where: { $0 == 10 || $0 == 13 }) {
            let lineData = Data(data[..<index])
            var removeEnd = index + 1
            if data[index] == 13, removeEnd < data.count, data[removeEnd] == 10 {
                removeEnd += 1
            }
            data.removeSubrange(..<removeEnd)
            if lineData.isEmpty { continue }
            let line = String(decoding: lineData, as: UTF8.self)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

enum CommandRunner {
    static func collect(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL? = nil
    ) async throws -> (stdout: String, stderr: String, code: Int32) {
        let running = CollectedProcess()
        return try await running.run(
            executable: executable,
            arguments: arguments,
            environment: environment,
            directory: directory
        )
    }
}

private final class CollectedProcess: @unchecked Sendable {
    let process = Process()

    func run(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        directory: URL?
    ) async throws -> (stdout: String, stderr: String, code: Int32) {
        let stdout = Pipe()
        let stderr = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.qualityOfService = .userInitiated
        if let directory {
            process.currentDirectoryURL = directory
        }
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()

        return try await withTaskCancellationHandler {
            async let out = Self.readAll(stdout.fileHandleForReading)
            async let err = Self.readAll(stderr.fileHandleForReading)
            let output = try await out
            let errors = try await err
            let code: Int32 = await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    if self.process.isRunning {
                        self.process.waitUntilExit()
                    }
                    continuation.resume(returning: self.process.terminationStatus)
                }
            }
            return (
                String(decoding: output, as: UTF8.self),
                String(decoding: errors, as: UTF8.self),
                code
            )
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func readAll(_ handle: FileHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var data = Data()
                do {
                    while true {
                        if let chunk = try handle.read(upToCount: 64 * 1024), !chunk.isEmpty {
                            data.append(chunk)
                        } else {
                            break
                        }
                    }
                    continuation.resume(returning: data)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
