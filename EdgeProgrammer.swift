import SwiftUI
import AppKit
import UniformTypeIdentifiers
import Darwin

enum ExecutableLocator {
    static func find(_ name: String, override: String? = nil, locations: [String],
                     environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        let custom = override?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidates = custom.isEmpty
            ? locations + (environment["PATH"] ?? "").split(separator: ":")
                .filter { $0.hasPrefix("/") }.map { "\($0)/\(name)" }
            : [(custom as NSString).expandingTildeInPath]
        return candidates.first { path in
            var directory: ObjCBool = false
            return path.hasPrefix("/")
                && FileManager.default.fileExists(atPath: path, isDirectory: &directory)
                && !directory.boolValue && FileManager.default.isExecutableFile(atPath: path)
        }
    }
}

final class ProcessOutputDrain: @unchecked Sendable {
    private let handle: FileHandle
    private let lock = NSLock()
    private let finished = DispatchGroup()
    private var output = ""

    init(handle: FileHandle) {
        self.handle = handle
        finished.enter()
    }

    func start(onChunk: @escaping @Sendable (String) -> Void) {
        DispatchQueue.global(qos: .utility).async { [self] in
            defer { finished.leave() }
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                let text = String(decoding: data, as: UTF8.self)
                lock.lock()
                output += text
                lock.unlock()
                onChunk(text)
            }
        }
    }

    func waitUntilFinished(timeout: DispatchTime) -> Bool {
        finished.wait(timeout: timeout) == .success
    }

    func snapshot() -> String {
        lock.lock()
        defer { lock.unlock() }
        return output
    }
}

enum ProcessOutputDrainSelfTest {
    static func run() -> Bool {
        let process = Process()
        let pipe = Pipe()
        let expected = "erase 25%\rerase 100%\nDone\n"
        process.executableURL = URL(fileURLWithPath: "/usr/bin/printf")
        process.arguments = ["%s", expected]
        process.standardOutput = pipe
        process.standardError = pipe

        let drain = ProcessOutputDrain(handle: pipe.fileHandleForReading)
        do {
            try process.run()
            drain.start { _ in }
            process.waitUntilExit()
            return process.terminationStatus == 0
                && drain.waitUntilFinished(timeout: .now() + 2)
                && drain.snapshot() == expected
        } catch {
            return false
        }
    }
}

enum FPGAProgramBoard: String, CaseIterable, Identifiable {
    case edgeSpartan7
    case apexSurveyor6

    var id: String { rawValue }

    var title: String {
        switch self {
        case .edgeSpartan7: return "EDGE Spartan-7"
        case .apexSurveyor6: return "Apex Surveyor-6"
        }
    }

    var detail: String {
        switch self {
        case .edgeSpartan7: return "XC7S15-1FTGB196 • FT2232 • 50 MHz"
        case .apexSurveyor6: return "XC6SLX9-2TQG144 • FT2232 • 20 MHz"
        }
    }

    var cable: String { "ft2232" }

    var flashPart: String {
        switch self {
        case .edgeSpartan7: return "xc7s15"
        case .apexSurveyor6: return "xc6slx9tqg144"
        }
    }

    var bitHeaderToken: String {
        switch self {
        case .edgeSpartan7: return "7s15ftgb196"
        case .apexSurveyor6: return "6slx9tqg144"
        }
    }
}

enum ProgrammingMode: String, CaseIterable, Identifiable {
    case sram
    case flash

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sram: return "SRAM (ชั่วคราว)"
        case .flash: return "SPI Flash (ถาวร)"
        }
    }

    var description: String {
        switch self {
        case .sram:
            return "โหลดวงจรเข้า FPGA โดยตรง เหมาะสำหรับทดลอง และจะหายเมื่อปิดไฟบอร์ด"
        case .flash:
            return "เขียนลงหน่วยความจำถาวร พร้อมตรวจสอบข้อมูล บอร์ดจะโหลดวงจรนี้เมื่อเปิดเครื่องใหม่"
        }
    }
}

enum ProgrammerCommands {
    static func detect(board: FPGAProgramBoard) -> [String] {
        ["-c", board.cable, "--detect"]
    }

    static func clearFlash(board: FPGAProgramBoard) -> [String] {
        ["-c", board.cable, "--fpga-part", board.flashPart, "-f", "--bulk-erase"]
    }

    static func program(board: FPGAProgramBoard, mode: ProgrammingMode, filePath: String) -> [String] {
        var arguments = ["-c", board.cable]
        if mode == .flash {
            arguments += ["--fpga-part", board.flashPart, "-f", "--verify"]
        } else {
            arguments.append("-m")
        }
        arguments.append(filePath)
        return arguments
    }
}

enum BitstreamInspector {
    static func detectedBoard(at url: URL) -> FPGAProgramBoard? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let prefix = (try? handle.read(upToCount: 16_384)) ?? nil
        guard let prefix else { return nil }
        let text = String(decoding: prefix, as: UTF8.self).lowercased()
        return FPGAProgramBoard.allCases.first { text.contains($0.bitHeaderToken) }
    }
}

@MainActor
final class ProgrammerModel: ObservableObject {
    @Published var selectedFile: URL?
    @Published var board: FPGAProgramBoard = .edgeSpartan7
    @Published var mode: ProgrammingMode = .sram
    @Published var isRunning = false
    @Published var statusText = "พร้อมใช้งาน"
    @Published var statusColor = Color.secondary
    @Published private(set) var logText = "เลือกไฟล์ .bit แล้วกดตรวจหาบอร์ดหรือ Program\n"
    @Published var showFlashConfirmation = false
    @Published var showClearFlashConfirmation = false
    @Published var showMissingLoaderAlert = false
    @Published var showInvalidFileAlert = false
    @Published var showBoardMismatchAlert = false
    @Published var detectedWrongBoard: FPGAProgramBoard?
    @Published var customLoaderPath = UserDefaults.standard.string(forKey: "customLoaderPath") ?? ""

    private var process: Process?
    private var outputPipe: Pipe?
    private var activeRunID: UUID?
    private lazy var uiLog = UILogBuffer(initialText: logText) { [weak self] text in
        self?.logText = text
    }

    init() {
        if let storedMode = UserDefaults.standard.string(forKey: "programmingMode"),
           let restoredMode = ProgrammingMode(rawValue: storedMode) {
            mode = restoredMode
        }
        if let storedBoard = UserDefaults.standard.string(forKey: "programBoard"),
           let restoredBoard = FPGAProgramBoard(rawValue: storedBoard) {
            board = restoredBoard
        }

        if let storedPath = UserDefaults.standard.string(forKey: "lastBitstreamPath") {
            let url = URL(fileURLWithPath: storedPath)
            if FileManager.default.fileExists(atPath: url.path) {
                selectedFile = url
            }
        }
    }

    var loaderPath: String? {
        let environmentOverride = ProcessInfo.processInfo.environment["EDGE_PROGRAMMER_LOADER_PATH"]
        return ExecutableLocator.find("openFPGALoader", override: environmentOverride ?? customLoaderPath, locations: [
            "/opt/homebrew/bin/openFPGALoader",
            "/usr/local/bin/openFPGALoader",
            "/opt/local/bin/openFPGALoader"
        ])
    }

    func chooseLoader() {
        let panel = NSOpenPanel()
        panel.title = "เลือก openFPGALoader executable"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            customLoaderPath = url.path
            UserDefaults.standard.set(url.path, forKey: "customLoaderPath")
        }
    }

    func resetLoader() {
        customLoaderPath = ""
        UserDefaults.standard.removeObject(forKey: "customLoaderPath")
    }

    var commandPreview: String {
        let filename = selectedFile?.lastPathComponent ?? "FILE.bit"
        return (["openFPGALoader"] + ProgrammerCommands.program(board: board, mode: mode, filePath: filename))
            .map(Self.shellQuoted)
            .joined(separator: " ")
    }

    func chooseFile() {
        let panel = NSOpenPanel()
        panel.title = "เลือกไฟล์ Bitstream"
        panel.prompt = "เลือกไฟล์"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let bitType = UTType(filenameExtension: "bit") {
            panel.allowedContentTypes = [bitType]
        }
        if let currentDirectory = selectedFile?.deletingLastPathComponent() {
            panel.directoryURL = currentDirectory
        }

        if panel.runModal() == .OK, let url = panel.url {
            selectedFile = url
            UserDefaults.standard.set(url.path, forKey: "lastBitstreamPath")
            statusText = "เลือกไฟล์แล้ว"
            statusColor = .blue
            appendLog("เลือกไฟล์: \(url.path)\n")
        }
    }

    func useBuiltBitstream(_ url: URL, sourceName: String) {
        guard url.pathExtension.lowercased() == "bit",
              FileManager.default.fileExists(atPath: url.path) else { return }
        selectedFile = url
        if let detectedBoard = BitstreamInspector.detectedBoard(at: url) {
            board = detectedBoard
            UserDefaults.standard.set(detectedBoard.rawValue, forKey: "programBoard")
            appendLog("เลือกบอร์ดอัตโนมัติจาก Bitstream: \(detectedBoard.title)\n")
        }
        UserDefaults.standard.set(url.path, forKey: "lastBitstreamPath")
        statusText = "รับไฟล์จาก \(sourceName) แล้ว"
        statusColor = .green
        appendLog("เลือกไฟล์จาก \(sourceName): \(url.path)\n")
    }

    func changeMode(_ newMode: ProgrammingMode) {
        mode = newMode
        UserDefaults.standard.set(newMode.rawValue, forKey: "programmingMode")
    }

    func changeBoard(_ newBoard: FPGAProgramBoard) {
        board = newBoard
        UserDefaults.standard.set(newBoard.rawValue, forKey: "programBoard")
        statusText = "เลือก \(newBoard.title)"
        statusColor = .blue
        appendLog("เลือกบอร์ด: \(newBoard.title) (\(newBoard.detail))\n")
    }

    func detectBoard() {
        run(
            arguments: ProgrammerCommands.detect(board: board),
            actionName: "กำลังตรวจหา \(board.title)",
            successMessage: "ตรวจพบบอร์ดและ JTAG พร้อมใช้งาน"
        )
    }

    func requestProgramming() {
        guard validateSelectedFile() else { return }
        if mode == .flash {
            showFlashConfirmation = true
        } else {
            programNow()
        }
    }

    func programNow() {
        guard validateSelectedFile(), let selectedFile else { return }

        let arguments = ProgrammerCommands.program(board: board, mode: mode, filePath: selectedFile.path)

        let action = mode == .flash ? "กำลังเขียน SPI Flash" : "กำลังโหลดเข้า SRAM"
        let success = mode == .flash ? "เขียนและตรวจสอบ SPI Flash สำเร็จ" : "Program SRAM สำเร็จ"
        run(arguments: arguments, actionName: action, successMessage: success)
    }

    func requestClearFlash() {
        guard !isRunning else { return }
        showClearFlashConfirmation = true
    }

    func clearFlashNow() {
        run(
            arguments: ProgrammerCommands.clearFlash(board: board),
            actionName: "กำลังล้าง SPI Flash ของ \(board.title)",
            successMessage: "ล้าง SPI Flash สำเร็จ — กรุณาปิดและเปิดบอร์ดใหม่"
        )
    }

    func cancel() {
        guard let process, process.isRunning else { return }
        appendLog("\nกำลังยกเลิก...\n")
        process.terminate()
        statusText = "ยกเลิกแล้ว"
        statusColor = .orange
    }

    func clearLog() {
        uiLog.clear()
    }

    private func validateSelectedFile() -> Bool {
        guard let selectedFile,
              selectedFile.pathExtension.lowercased() == "bit",
              FileManager.default.fileExists(atPath: selectedFile.path) else {
            showInvalidFileAlert = true
            return false
        }
        if let detectedBoard = BitstreamInspector.detectedBoard(at: selectedFile), detectedBoard != board {
            detectedWrongBoard = detectedBoard
            showBoardMismatchAlert = true
            statusText = "ไฟล์ .bit ไม่ตรงกับบอร์ด"
            statusColor = .red
            appendLog("✗ ไฟล์นี้เป็น \(detectedBoard.title) แต่เลือก \(board.title)\n")
            return false
        }
        return true
    }

    private func run(arguments: [String], actionName: String, successMessage: String) {
        guard !isRunning else { return }
        guard let loaderPath else {
            showMissingLoaderAlert = true
            statusText = "ไม่พบ openFPGALoader"
            statusColor = .red
            return
        }

        let newProcess = Process()
        let pipe = Pipe()
        newProcess.executableURL = URL(fileURLWithPath: loaderPath)
        newProcess.arguments = arguments
        newProcess.standardOutput = pipe
        newProcess.standardError = pipe

        let runID = UUID()
        let outputDrain = ProcessOutputDrain(handle: pipe.fileHandleForReading)

        process = newProcess
        outputPipe = pipe
        activeRunID = runID
        isRunning = true
        statusText = actionName
        statusColor = .blue

        let displayedCommand = ([loaderPath] + arguments).map(Self.shellQuoted).joined(separator: " ")
        appendLog("\n$ \(displayedCommand)\n")

        newProcess.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.global(qos: .utility).async {
                let streamClosed = outputDrain.waitUntilFinished(timeout: .now() + 2)
                DispatchQueue.main.async {
                    guard let self, self.activeRunID == runID else { return }
                    self.isRunning = false
                    self.process = nil
                    self.outputPipe = nil
                    self.activeRunID = nil

                    if !streamClosed {
                        self.appendLog("\n⚠ stream ของ Log ปิดช้ากว่าปกติ แต่ตัวโปรแกรมจบการทำงานแล้ว\n")
                    }

                    if finishedProcess.terminationStatus == 0 {
                        self.statusText = successMessage
                        self.statusColor = .green
                        self.appendLog("\n✓ \(successMessage)\n")
                    } else if finishedProcess.terminationReason == .uncaughtSignal {
                        self.statusText = "ยกเลิกแล้ว"
                        self.statusColor = .orange
                        self.appendLog("\nยกเลิกการทำงานแล้ว\n")
                    } else {
                        self.statusText = "ไม่สำเร็จ (รหัส \(finishedProcess.terminationStatus))"
                        self.statusColor = .red
                        self.appendLog("\n✗ ทำงานไม่สำเร็จ กรุณาตรวจรายละเอียดด้านบน\n")
                    }
                }
            }
        }

        do {
            try newProcess.run()
            outputDrain.start { [weak self] text in
                DispatchQueue.main.async {
                    guard let self, self.activeRunID == runID else { return }
                    self.appendLog(text)
                }
            }
        } catch {
            try? pipe.fileHandleForWriting.close()
            isRunning = false
            process = nil
            outputPipe = nil
            activeRunID = nil
            statusText = "เปิด openFPGALoader ไม่สำเร็จ"
            statusColor = .red
            appendLog("เกิดข้อผิดพลาด: \(error.localizedDescription)\n")
        }
    }

    private func appendLog(_ text: String) {
        uiLog.append(text.replacingOccurrences(of: "\r", with: "\n"))
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil {
            return value
        }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.callout.weight(.medium))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

struct ContentView: View {
    @ObservedObject var model: ProgrammerModel

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(spacing: 18) {
                    loaderCard
                    boardCard
                    bitstreamCard
                    modeCard
                    actionArea
                    logCard
                }
                .padding(24)
            }
        }
        .frame(minWidth: 680, minHeight: 650)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert("ไม่พบ openFPGALoader", isPresented: $model.showMissingLoaderAlert) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text("ติดตั้งด้วยคำสั่ง brew install openfpgaloader แล้วเปิดแอปอีกครั้ง")
        }
        .alert("กรุณาเลือกไฟล์ .bit", isPresented: $model.showInvalidFileAlert) {
            Button("เลือกไฟล์") { model.chooseFile() }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("ต้องเลือกไฟล์ Bitstream ที่ยังอยู่ในเครื่องก่อนเริ่ม Program")
        }
        .alert("ไฟล์ .bit ไม่ตรงกับบอร์ด", isPresented: $model.showBoardMismatchAlert) {
            Button("ตกลง", role: .cancel) {}
        } message: {
            Text("ตรวจพบว่าไฟล์นี้สร้างสำหรับ \(model.detectedWrongBoard?.title ?? "บอร์ดคนละรุ่น") แต่ขณะนี้เลือก \(model.board.title) แอปจึงหยุดไว้เพื่อป้องกันการโหลด Bitstream ผิด FPGA")
        }
        .confirmationDialog(
            "ยืนยันการเขียน SPI Flash",
            isPresented: $model.showFlashConfirmation,
            titleVisibility: .visible
        ) {
            Button("เขียน SPI Flash", role: .destructive) {
                model.programNow()
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("การเขียน Flash ใช้เวลานานกว่า SRAM กรุณาอย่าถอดสาย USB หรือปิดไฟบอร์ดจนกว่าจะเสร็จ")
        }
        .confirmationDialog(
            "ล้างข้อมูลทั้งหมดใน SPI Flash?",
            isPresented: $model.showClearFlashConfirmation,
            titleVisibility: .visible
        ) {
            Button("ล้าง SPI Flash", role: .destructive) {
                model.clearFlashNow()
            }
            Button("ยกเลิก", role: .cancel) {}
        } message: {
            Text("คำสั่งนี้ย้อนกลับไม่ได้ หลังล้างเสร็จวงจรปัจจุบันอาจยังทำงานอยู่จนกว่าจะปิดและเปิดบอร์ดใหม่ กรุณาอย่าถอดสายหรือปิดไฟระหว่างกำลังล้าง")
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "cpu.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color(red: 0.13, green: 0.43, blue: 0.88), Color(red: 0.31, green: 0.22, blue: 0.76)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text("Spartan Build & Program")
                    .font(.title2.weight(.bold))
                Text("Local Build และ Program EDGE Spartan-7 / Apex Surveyor-6 จาก Mac")
                    .foregroundStyle(.secondary)
            }

            Spacer()
            StatusPill(text: model.statusText, color: model.statusColor)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .background(.regularMaterial)
    }

    private var boardCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                Picker("บอร์ดที่จะ Program", selection: Binding(
                    get: { model.board },
                    set: { model.changeBoard($0) }
                )) {
                    ForEach(FPGAProgramBoard.allCases) { board in
                        Text(board.title).tag(board)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isRunning)

                HStack {
                    Text(model.board.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Label("ตรวจชนิด .bit ก่อน Program", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                }
            }
            .padding(.vertical, 5)
        } label: {
            Label("บอร์ด", systemImage: "rectangle.connected.to.line.below")
        }
    }

    private var loaderCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Label(model.loaderPath == nil ? "ยังไม่พบ openFPGALoader" : "พบ openFPGALoader",
                      systemImage: model.loaderPath == nil ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(model.loaderPath == nil ? Color.orange : Color.green)
                Text(model.loaderPath ?? (model.customLoaderPath.isEmpty
                     ? "ติดตั้งด้วย brew install openfpgaloader แล้วกดตรวจอีกครั้ง"
                     : "เปิด executable ไม่ได้: \(model.customLoaderPath)"))
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                HStack {
                    Link("วิธีติดตั้ง", destination: URL(string: "https://trabucayre.github.io/openFPGALoader/guide/install.html#macos")!)
                    Spacer()
                    Button("ตรวจอีกครั้ง") { model.objectWillChange.send() }
                    Button("เลือก executable…") { model.chooseLoader() }
                    if !model.customLoaderPath.isEmpty {
                        Button("ค้นหาอัตโนมัติ") { model.resetLoader() }
                    }
                }
                .disabled(model.isRunning)
            }
            .padding(.vertical, 5)
        } label: {
            Label("เครื่องมือ Program", systemImage: "wrench.and.screwdriver")
        }
    }

    private var bitstreamCard: some View {
        GroupBox {
            HStack(spacing: 12) {
                Image(systemName: model.selectedFile == nil ? "doc.badge.plus" : "doc.fill")
                    .font(.title2)
                    .foregroundStyle(model.selectedFile == nil ? Color.secondary : Color.accentColor)

                VStack(alignment: .leading, spacing: 3) {
                    Text(model.selectedFile?.lastPathComponent ?? "ยังไม่ได้เลือกไฟล์")
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    Text(model.selectedFile?.deletingLastPathComponent().path ?? "รองรับไฟล์ .bit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
                Button("เลือกไฟล์…") { model.chooseFile() }
                    .controlSize(.large)
                    .disabled(model.isRunning)
            }
            .padding(.vertical, 5)
        } label: {
            Label("ไฟล์ Bitstream", systemImage: "doc.text")
        }
    }

    private var modeCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("โหมด", selection: Binding(
                    get: { model.mode },
                    set: { model.changeMode($0) }
                )) {
                    ForEach(ProgrammingMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(model.isRunning)

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: model.mode == .sram ? "bolt.fill" : "externaldrive.fill.badge.checkmark")
                        .foregroundStyle(model.mode == .sram ? .blue : .orange)
                    Text(model.mode.description)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Text(model.commandPreview)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 7))
            }
            .padding(.vertical, 5)
        } label: {
            Label("วิธี Program", systemImage: "arrow.down.to.line.compact")
        }
    }

    private var actionArea: some View {
        HStack(spacing: 12) {
            Button {
                model.detectBoard()
            } label: {
                Label("ตรวจหาบอร์ด", systemImage: "magnifyingglass")
                    .frame(minWidth: 110)
            }
            .controlSize(.large)
            .disabled(model.isRunning)

            Button(role: .destructive) {
                model.requestClearFlash()
            } label: {
                Label("ล้าง Flash…", systemImage: "trash")
            }
            .controlSize(.large)
            .disabled(model.isRunning)

            Spacer()

            if model.isRunning {
                ProgressView()
                    .controlSize(.small)
                Button("ยกเลิก", role: .cancel) { model.cancel() }
                    .controlSize(.large)
            }

            Button {
                model.requestProgramming()
            } label: {
                Label(model.mode == .flash ? "เขียน SPI Flash" : "Program SRAM", systemImage: "play.fill")
                    .frame(minWidth: 130)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(model.mode == .flash ? .orange : .accentColor)
            .disabled(model.isRunning || model.selectedFile == nil)
            .keyboardShortcut(.return, modifiers: [.command])
        }
    }

    private var logCard: some View {
        GroupBox {
            VStack(spacing: 8) {
                ReadOnlyLogView(text: model.logText)
                    .frame(height: 220)

                HStack {
                    Text("อย่าถอดสายหรือปิดไฟระหว่างกำลัง Program")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("ล้าง Log") { model.clearLog() }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .disabled(model.isRunning)
                }
            }
            .padding(.vertical, 5)
        } label: {
            Label("ผลการทำงาน", systemImage: "terminal")
        }
    }
}

enum AppSection: Hashable {
    case setup
    case localBuild
    case program
}

struct RootContentView: View {
    @StateObject private var programmerModel = ProgrammerModel()
    @State private var selectedSection: AppSection = UserDefaults.standard.bool(forKey: "didOpenSetupGuide")
        ? .localBuild : .setup

    var body: some View {
        TabView(selection: $selectedSection) {
            SetupGuideView {
                selectedSection = .localBuild
            } onProgram: {
                selectedSection = .program
            }
            .onAppear { UserDefaults.standard.set(true, forKey: "didOpenSetupGuide") }
            .tabItem { Label("เริ่มต้นใช้งาน", systemImage: "book") }
            .tag(AppSection.setup)

            LocalBuildView { bitstreamURL in
                programmerModel.useBuiltBitstream(bitstreamURL, sourceName: "Local Build")
                selectedSection = .program
            }
            .tabItem {
                Label("Local Build", systemImage: "shippingbox.fill")
            }
            .tag(AppSection.localBuild)

            ContentView(model: programmerModel)
                .tabItem {
                    Label("Program Board", systemImage: "cpu")
                }
                .tag(AppSection.program)
        }
        .frame(minWidth: 760, minHeight: 700)
    }
}

@main
struct EdgeProgrammerApp: App {
    init() {
        if CommandLine.arguments.contains("--self-test") {
            let sample = "/tmp/example.bit"
            let edgeSRAM = ProgrammerCommands.program(board: .edgeSpartan7, mode: .sram, filePath: sample)
            let edgeFlash = ProgrammerCommands.program(board: .edgeSpartan7, mode: .flash, filePath: sample)
            let apexSRAM = ProgrammerCommands.program(board: .apexSurveyor6, mode: .sram, filePath: sample)
            let apexFlash = ProgrammerCommands.program(board: .apexSurveyor6, mode: .flash, filePath: sample)
            let environment = ProcessInfo.processInfo.environment
            let edgeHeaderPassed = environment["EDGE_SPARTAN7_TEST_BIT"].map {
                BitstreamInspector.detectedBoard(at: URL(fileURLWithPath: $0)) == .edgeSpartan7
            } ?? true
            let apexHeaderPassed = environment["EDGE_SPARTAN6_TEST_BIT"].map {
                BitstreamInspector.detectedBoard(at: URL(fileURLWithPath: $0)) == .apexSurveyor6
            } ?? true
            let passed = ProgrammerCommands.detect(board: .edgeSpartan7) == ["-c", "ft2232", "--detect"]
                && ProgrammerCommands.clearFlash(board: .edgeSpartan7) == ["-c", "ft2232", "--fpga-part", "xc7s15", "-f", "--bulk-erase"]
                && ProgrammerCommands.clearFlash(board: .apexSurveyor6) == ["-c", "ft2232", "--fpga-part", "xc6slx9tqg144", "-f", "--bulk-erase"]
                && edgeSRAM == ["-c", "ft2232", "-m", sample]
                && edgeFlash == ["-c", "ft2232", "--fpga-part", "xc7s15", "-f", "--verify", sample]
                && apexSRAM == ["-c", "ft2232", "-m", sample]
                && apexFlash == ["-c", "ft2232", "--fpga-part", "xc6slx9tqg144", "-f", "--verify", sample]
                && edgeHeaderPassed
                && apexHeaderPassed
                && ProcessOutputDrainSelfTest.run()
                && VHDLSupportSelfTest.run()
                && PinMappingSupportSelfTest.run()
                && LogSupportSelfTest.run()
                && LocalBuildSelfTest.run()
            print(passed ? "SELF-TEST PASSED" : "SELF-TEST FAILED")
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--local-docker-self-test") {
            let passed = LocalBuildSelfTest.runDockerIntegration()
            print(passed ? "LOCAL DOCKER SELF-TEST PASSED" : "LOCAL DOCKER SELF-TEST FAILED")
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--local-result-self-test") {
            let passed = LocalBuildSelfTest.validateExistingResult()
            print(passed ? "LOCAL RESULT SELF-TEST PASSED" : "LOCAL RESULT SELF-TEST FAILED")
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        BuildNotifications.shared.configure()
        if CommandLine.arguments.contains("--notification-self-test") {
            Task {
                let passed = await BuildNotifications.shared.runSmokeTest()
                exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 900, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
