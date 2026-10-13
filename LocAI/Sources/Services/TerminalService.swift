import Foundation

// Everything in this file is explicitly `nonisolated`: the project uses
// SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor, and command execution must
// never run on (or block) the main actor.

/// The outcome of one shell command.
nonisolated struct TerminalResult: Sendable {
    var command: String
    var exitCode: Int32
    var output: String
    var timedOut: Bool
    var truncated: Bool
    var launchError: String?

    /// Text fed back to the model as the next message.
    var forModel: String {
        if let launchError {
            return "<terminal_output status=\"error\">Could not run the command: \(launchError)</terminal_output>"
        }
        var attributes = "exit_code=\"\(exitCode)\""
        if timedOut { attributes += " timed_out=\"true\"" }
        if truncated { attributes += " truncated=\"true\"" }
        let body = output.isEmpty ? "(no output)" : output
        return "<terminal_output \(attributes)>\n\(body)\n</terminal_output>"
    }
}

nonisolated enum TerminalService {
    static var isSupported: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// True when the app runs inside the macOS App Sandbox. In that case a
    /// child shell inherits the sandbox and can only see the app container.
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Runs `command` with `/bin/zsh -l -c`, merging stdout and stderr.
    /// Never throws: failures are reported inside the result. Cancelling the
    /// calling task terminates the process.
    static func run(command: String, workingDirectory: URL, timeout: TimeInterval, maxOutputBytes: Int) async -> TerminalResult {
        #if os(macOS)
        return await CommandRunner().run(
            command: command,
            workingDirectory: workingDirectory,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )
        #else
        return TerminalResult(
            command: command, exitCode: -1, output: "", timedOut: false, truncated: false,
            launchError: "Terminal access is only available on macOS."
        )
        #endif
    }
}

// MARK: - Tool-call protocol

/// Finds `<terminal>command</terminal>` blocks in model output. The protocol
/// is plain text on purpose: it works with every chat template and every
/// backend, unlike native tool calling which only some models support.
nonisolated enum TerminalCommandParser {
    static let openTag = "<terminal>"
    static let closeTag = "</terminal>"

    /// The first *complete* block. `end` is the index right after the closing
    /// tag, so the caller can discard anything the model wrote after it
    /// (typically an invented command output).
    static func firstCommand(in text: String) -> (command: String, end: String.Index)? {
        guard let open = text.range(of: openTag) else { return nil }
        guard let close = text.range(of: closeTag, range: open.upperBound..<text.endIndex) else { return nil }
        let command = clean(String(text[open.upperBound..<close.lowerBound]))
        guard !command.isEmpty else { return nil }
        return (command, close.upperBound)
    }

    /// Small models like to wrap the command in a code fence or prefix a `$`.
    static func clean(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            var lines = s.components(separatedBy: "\n")
            lines.removeFirst()
            if let last = lines.last, last.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                lines.removeLast()
            }
            s = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasPrefix("$ "), !s.contains("\n") {
            s.removeFirst(2)
        }
        return s
    }
}

nonisolated enum TerminalPrompt {
    static func instructions(workingDirectory: String) -> String {
        """
        You have access to the user's Mac terminal (macOS, zsh). Use it when a task needs real information from, or actions on, this computer: files, system info, running programs.

        To run a command, write exactly one block and then stop writing:
        <terminal>
        command here
        </terminal>

        Rules:
        - Send only one command per reply. Write nothing after the closing tag and wait for the result.
        - The result arrives in the next message inside <terminal_output> tags. Never guess or invent command output.
        - Commands run non-interactively with a time limit and no keyboard input, so avoid editors, pagers and anything that asks questions.
        - Prefer short read-only commands. Do not delete, overwrite or install anything, and do not use sudo, unless the user clearly asked for it.
        - If a command fails, read the error and either fix the command or explain the problem.
        - When you have enough information, answer the user in the user's language without any <terminal> block. To show a command only as an example, put it in a normal markdown code block instead.

        Working folder: \(workingDirectory)
        System: \(ProcessInfo.processInfo.operatingSystemVersionString)
        """
    }

    static let finalAnswerNotice = "You have used all the terminal commands allowed for this reply. Do not write any <terminal> block now: answer the user using the information you already have."
}

// MARK: - Process runner (macOS)

#if os(macOS)
/// One-shot command runner. All mutable state is guarded by `lock`.
///
/// Design notes:
/// - stdout/stderr share one pipe so the model sees them interleaved.
/// - The pipe is drained by a dedicated thread so a chatty command can never
///   fill the pipe buffer and deadlock.
/// - We do not wait for EOF forever: a background grandchild may keep the pipe
///   open after the shell exits, so we give the reader a short grace period.
/// - Only the head and the tail of very long output are kept (errors are
///   usually at the end) to protect the model's context window.
nonisolated private final class CommandRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var continuation: CheckedContinuation<TerminalResult, Never>?
    private var command = ""
    private var finished = false
    private var cancelled = false
    private var timedOut = false

    private var head = Data()
    private var tail = Data()
    private var totalBytes = 0
    private var headLimit = 5_000
    private var tailLimit = 3_000

    func run(command: String, workingDirectory: URL, timeout: TimeInterval, maxOutputBytes: Int) async -> TerminalResult {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<TerminalResult, Never>) in
                self.start(
                    command: command,
                    workingDirectory: workingDirectory,
                    timeout: timeout,
                    maxOutputBytes: maxOutputBytes,
                    continuation: continuation
                )
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func start(
        command: String,
        workingDirectory: URL,
        timeout: TimeInterval,
        maxOutputBytes: Int,
        continuation: CheckedContinuation<TerminalResult, Never>
    ) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", command]
        process.currentDirectoryURL = workingDirectory

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "dumb"
        environment["NO_COLOR"] = "1"
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        environment["GIT_TERMINAL_PROMPT"] = "0"
        if environment["LC_ALL"] == nil { environment["LC_ALL"] = "en_US.UTF-8" }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        let readerDone = DispatchSemaphore(value: 0)

        lock.lock()
        self.process = process
        self.continuation = continuation
        self.command = command
        let cap = max(1_000, maxOutputBytes)
        headLimit = cap * 65 / 100
        tailLimit = cap - headLimit
        let alreadyCancelled = cancelled
        lock.unlock()

        process.terminationHandler = { [self] terminated in
            DispatchQueue.global().async {
                _ = readerDone.wait(timeout: .now() + 0.3)
                self.finish(exitCode: terminated.terminationStatus, launchError: nil)
            }
        }

        do {
            try process.run()
        } catch {
            finish(exitCode: -1, launchError: error.localizedDescription)
            return
        }
        // The parent must close its copy of the write end, otherwise the
        // reader never sees EOF.
        try? pipe.fileHandleForWriting.close()

        let reader = pipe.fileHandleForReading
        Thread.detachNewThread { [self] in
            while true {
                let chunk = reader.availableData
                if chunk.isEmpty { break }
                self.append(chunk)
            }
            readerDone.signal()
        }

        if timeout > 0 {
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [self] in
                self.timeoutFired()
            }
        }
        if alreadyCancelled { cancel() }
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
        terminateTree()
    }

    private func timeoutFired() {
        lock.lock()
        if finished {
            lock.unlock()
            return
        }
        timedOut = true
        lock.unlock()
        terminateTree()
    }

    /// Stops the shell and, best effort, its direct children.
    private func terminateTree() {
        lock.lock()
        let process = self.process
        lock.unlock()
        guard let process, process.isRunning else { return }

        let pid = process.processIdentifier
        Self.signalChildren(of: pid, signal: "TERM")
        process.terminate()

        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if process.isRunning {
                Self.signalChildren(of: pid, signal: "KILL")
                kill(pid, SIGKILL)
            }
        }
    }

    private static func signalChildren(of pid: Int32, signal: String) {
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        helper.arguments = ["-\(signal)", "-P", "\(pid)"]
        helper.standardOutput = FileHandle.nullDevice
        helper.standardError = FileHandle.nullDevice
        helper.standardInput = FileHandle.nullDevice
        try? helper.run()
        helper.waitUntilExit()
    }

    private func append(_ data: Data) {
        lock.lock()
        defer { lock.unlock() }
        totalBytes += data.count
        var remaining = data
        if head.count < headLimit {
            let take = min(headLimit - head.count, remaining.count)
            head.append(remaining.prefix(take))
            remaining = Data(remaining.dropFirst(take))
        }
        if !remaining.isEmpty {
            tail.append(remaining)
            if tail.count > tailLimit {
                tail = Data(tail.suffix(tailLimit))
            }
        }
    }

    private func finish(exitCode: Int32, launchError: String?) {
        lock.lock()
        guard !finished, let continuation = self.continuation else {
            lock.unlock()
            return
        }
        finished = true
        self.continuation = nil

        let omitted = totalBytes - head.count - tail.count
        var text = String(decoding: head, as: UTF8.self)
        if omitted > 0 {
            text += "\n…[\(omitted) bytes omitted]…\n"
        }
        text += String(decoding: tail, as: UTF8.self)

        let result = TerminalResult(
            command: command,
            exitCode: exitCode,
            output: text.trimmingCharacters(in: .whitespacesAndNewlines),
            timedOut: timedOut,
            truncated: omitted > 0,
            launchError: launchError
        )
        lock.unlock()
        continuation.resume(returning: result)
    }
}
#endif
