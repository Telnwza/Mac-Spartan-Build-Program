import Foundation

@main
struct WorkflowHarness {
    struct CheckFailed: Error { let description: String }

    static func check(_ condition: Bool, _ description: String) throws {
        guard condition else { throw CheckFailed(description: description) }
        print("PASS: \(description)")
    }

    @MainActor
    static func waitForCompletion(_ model: LocalBuildModel) async throws {
        let deadline = ProcessInfo.processInfo.systemUptime + 300
        while model.isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                model.cancel()
                throw CheckFailed(description: "workflow timed out")
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @MainActor
    static func main() async throws {
        let env = ProcessInfo.processInfo.environment
        let root = URL(fileURLWithPath: env["EDGE_WORKFLOW_TEST_ROOT"]!, isDirectory: true)
        let repo = URL(fileURLWithPath: env["EDGE_WORKFLOW_SOURCE_ROOT"]!, isDirectory: true)
        let mode = CommandLine.arguments[1]
        let suiteName = "WorkflowHarness.\(root.lastPathComponent)"
        let defaults = UserDefaults(suiteName: suiteName)!
        if mode != "live-warm" { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(root.appendingPathComponent("builds").path, forKey: "localBuildRoot")
        defaults.set("1", forKey: "localMinimumFreeGiB")
        defaults.set(false, forKey: "localBuildNotifications")
        if let image = env["EDGE_LOCAL_TEST_DOCKER_IMAGE"] {
            defaults.set(image, forKey: "localDockerImage")
        }
        if let settings = env["EDGE_LOCAL_TEST_VIVADO_SETTINGS"] {
            defaults.set(settings, forKey: "localVivadoSettingsPath")
        }

        func model() -> LocalBuildModel {
            let value = LocalBuildModel(defaults: defaults)
            value.sourceFiles = [repo.appendingPathComponent("diagnostics/portable_smoke.vhd")]
            value.topEntity = "portable_smoke"
            value.constraintMode = .existingXDC
            value.selectedXDC = repo.appendingPathComponent("diagnostics/portable_smoke.xdc")
            return value
        }
        func control(_ data: [String: Any]) throws {
            try JSONSerialization.data(withJSONObject: data).write(to: root.appendingPathComponent("control.json"))
        }
        func commandCount(_ first: String, contains: String? = nil) throws -> Int {
            let text = try String(contentsOf: root.appendingPathComponent("commands.jsonl"))
            return try text.split(separator: "\n").filter { line in
                let args = try JSONDecoder().decode([String].self, from: Data(line.utf8))
                return args.first == first && (contains == nil || args.contains(where: { $0.contains(contains!) }))
            }.count
        }
        if mode.hasPrefix("live-") {
            let value = model()
            value.startBuild()
            try await waitForCompletion(value)
            for line in value.logText.split(separator: "\n")
                where line.contains("ตรวจ Environment:") || line.contains("ใช้ผลตรวจ Vivado เดิม")
                    || line.hasPrefix("Build:") {
                print(line)
            }
            print(value.statusText)
            try value.logText.write(to: root.appendingPathComponent(mode + ".log"), atomically: true, encoding: .utf8)
            try check(value.completedBitstream != nil, "real Docker \(mode) produced a validated bitstream")
            try check(value.logText.contains("ใช้ผลตรวจ Vivado เดิม") == (mode == "live-warm"),
                      "real Docker cache decision for \(mode)")
            defaults.synchronize()
            if mode == "live-warm" { defaults.removePersistentDomain(forName: suiteName) }
            return
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try check(model().dockerImage == LocalBuildTemplates.defaultDockerImage,
                  "fresh install uses the upstream image name")
        defaults.set("xilinx-vivado:2025.2-rosetta", forKey: "localDockerImage")
        try check(model().dockerImage == "xilinx-vivado:2025.2-rosetta",
                  "existing custom image setting is preserved")
        defaults.removeObject(forKey: "localDockerImage")

        let tools = root.appendingPathComponent("tools with spaces", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        let tool = tools.appendingPathComponent("fixture-tool")
        try "#!/bin/sh\nexit 0\n".write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        try check(ExecutableLocator.find("fixture-tool", locations: [], environment: ["PATH": tools.path]) == tool.path,
                  "tool discovery handles PATH entries with spaces")
        try check(ExecutableLocator.find("fixture-tool", override: "/missing/tool", locations: [tool.path]) == nil,
                  "invalid explicit executable does not silently select another tool")
        try check(ExecutableLocator.find("fixture-tool", override: tools.path, locations: []) == nil,
                  "tool discovery rejects directories")
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tool.path)
        try check(ExecutableLocator.find("fixture-tool", override: tool.path, locations: []) == nil,
                  "tool discovery rejects non-executable files")

        let setup = tools.appendingPathComponent("Vivado's settings64.sh")
        try "export WORKFLOW_SETUP_PASSED=yes\n".write(to: setup, atomically: true, encoding: .utf8)
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/bash")
        shell.arguments = ["-c", LocalBuildTemplates.vivadoCommand(
            settingsPath: setup.path, command: "test \"$WORKFLOW_SETUP_PASSED\" = yes", rosetta: false
        )]
        try shell.run()
        shell.waitUntilExit()
        try check(shell.terminationStatus == 0, "Vivado setup paths with spaces and apostrophes are shell quoted")
        try check(LocalBuildTemplates.vivadoCommand(settingsPath: setup.path, command: "true", rosetta: true)
                    .contains("if [ -f /opt/udev_stub.so ]"),
                  "Rosetta workaround is conditional for images without a stub")
        try check(!LocalBuildTemplates.vivadoCommand(settingsPath: setup.path, command: "true", rosetta: false)
                    .contains("LD_PRELOAD"), "Intel invocation does not inject the Rosetta workaround")

        try control([:])
        let cold = model()
        try check(cold.canBuild && !cold.environmentReady, "Build enabled before an environment check")
        cold.startBuild()
        try await waitForCompletion(cold)
        try check(cold.completedBitstream != nil, "cold Build checks environment and builds automatically")
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 1, "cold Build probes Vivado once")
        let warm = model()
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(warm.completedBitstream != nil, "new model reuses persisted environment")
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 1, "warm Build skips Vivado probe")
        warm.setBuildRoot(root.appendingPathComponent("other-builds").path)
        warm.setMinimumFreeGiB("1")
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 1, "storage changes do not repeat Vivado probe")
        warm.testEnvironment()
        try await waitForCompletion(warm)
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 2, "manual check forces a probe")
        try control(["image": "sha256:image-2"])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 3, "changed image invalidates cache")
        try control(["image": "sha256:image-2", "engine": "engine-2"])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 4, "changed Docker engine invalidates cache")
        warm.setVivadoSettingsPath("/other/settings64.sh")
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(try commandCount("run", contains: "LOCAL_ENV_PASS") == 5, "changed setup invalidates cache")
        let beforeDiskCheck = try commandCount("info")
        warm.setMinimumFreeGiB("1000")
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(try commandCount("info") == beforeDiskCheck, "insufficient disk stops before Docker")
        warm.setMinimumFreeGiB("1")
        try control(["engine_down": true])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(!warm.environmentReady && warm.statusText.contains("Docker Engine ไม่พร้อม"), "stopped Docker fails clearly")
        try control(["missing_image": true])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(!warm.environmentReady && warm.statusText.contains("ไม่พบ image"), "missing image blocks Build")
        try control(["platform": "linux/arm64"])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(!warm.environmentReady, "wrong image architecture blocks Build")
        try control(["probe_failure": true])
        warm.testEnvironment()
        try await waitForCompletion(warm)
        try check(!warm.environmentReady, "failed full check never becomes ready")
        try control(["build_failure": true])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(warm.completedBitstream == nil && warm.statusText.contains("ไม่สำเร็จ"), "VHDL failure never reports success")
        try control(["timing_failure": true])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(warm.completedBitstream == nil && warm.statusText.contains("Timing"), "timing failure never reports success")
        try control(["route_failure": true])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(warm.completedBitstream == nil && warm.statusText.contains("routing"), "routing failure never reports success")
        try control(["info_delay": 2])
        warm.startBuild()
        try await Task.sleep(nanoseconds: 100_000_000)
        warm.cancel()
        try control([:])
        warm.startBuild()
        try await waitForCompletion(warm)
        try check(warm.completedBitstream != nil, "cancelled check cannot overwrite a newer Build")
        let commands = try String(contentsOf: root.appendingPathComponent("commands.jsonl"))
            .split(separator: "\n").map { try JSONDecoder().decode([String].self, from: Data($0.utf8)) }
        let runs = commands.filter { $0.first == "run" }
        try check(runs.allSatisfy { $0.last?.contains("LD_PRELOAD") == LocalBuildTemplates.usesRosetta },
                  "environment probe and Build apply the same host-specific Rosetta workaround")
        try check(runs.allSatisfy { args in
            guard let bash = args.firstIndex(of: "/bin/bash"), bash > 0 else { return false }
            return args[bash - 1].hasPrefix("sha256:")
        }, "probe and Build both use immutable image IDs")
        print("WORKFLOW TESTS PASSED")
    }
}
