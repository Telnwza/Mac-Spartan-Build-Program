import Foundation

enum PinCategory: String, CaseIterable, Codable, Identifiable, Sendable {
    case clock
    case switches
    case buttons
    case leds
    case sevenSegment
    case digitSelect
    case lcd
    case uart
    case wifi
    case bluetooth
    case vga
    case camera
    case audio
    case converter
    case ps2
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .switches: return "Switch"
        case .buttons: return "Push Button"
        case .leds: return "LED"
        case .sevenSegment: return "7-Segment A–DP"
        case .digitSelect: return "Digit Select"
        case .lcd: return "LCD"
        case .uart: return "UART"
        case .wifi: return "Wi-Fi"
        case .bluetooth: return "Bluetooth"
        case .vga: return "VGA"
        case .camera: return "Camera"
        case .audio: return "Audio"
        case .converter: return "ADC / DAC"
        case .ps2: return "PS/2"
        case .other: return "อื่น ๆ"
        }
    }

    static func classify(label: String) -> PinCategory {
        let value = label.uppercased()
        if value.contains("OSC") { return .clock }
        if value.contains("PUSH BUTTON") { return .buttons }
        if value.contains("SEG_") { return .sevenSegment }
        if value.hasPrefix("DIGIT") { return .digitSelect }
        if value.contains("LED") { return .leds }
        if value.hasPrefix("SW") { return .switches }
        if value.contains("LCD") { return .lcd }
        if value.contains("UART") { return .uart }
        if value.contains("WIFI") { return .wifi }
        if value.contains("BT_") { return .bluetooth }
        if value.contains("VGA") { return .vga }
        if value.contains("CAM_") || value.contains("J5/CAM") { return .camera }
        if value.contains("AUDIO") { return .audio }
        if value.contains("ADC_") || value.contains("DAC_") { return .converter }
        if value.contains("PS2_") { return .ps2 }
        return .other
    }

    func matches(label: String) -> Bool {
        let value = label.uppercased()
        switch self {
        case .clock: return value.contains("OSC")
        case .switches: return value.hasPrefix("SW") && !value.contains("PUSH BUTTON")
        case .buttons: return value.contains("PUSH BUTTON")
        case .leds: return value.contains("LED")
        case .sevenSegment: return value.contains("SEG_")
        case .digitSelect: return value.hasPrefix("DIGIT")
        case .lcd: return value.contains("LCD")
        case .uart: return value.contains("UART")
        case .wifi: return value.contains("WIFI")
        case .bluetooth: return value.contains("BT_")
        case .vga: return value.contains("VGA")
        case .camera: return value.contains("CAM_") || value.contains("J5/CAM")
        case .audio: return value.contains("AUDIO")
        case .converter: return value.contains("ADC_") || value.contains("DAC_")
        case .ps2: return value.contains("PS2_")
        case .other: return Self.classify(label: label) == .other
        }
    }
}

extension PinOption {
    var category: PinCategory { PinCategory.classify(label: label) }
}

struct SignalPortInfo: Hashable, Sendable {
    let name: String
    let baseName: String
    let index: Int?

    init(_ name: String) {
        self.name = name
        guard let regex = try? NSRegularExpression(pattern: #"^(.+)\[(\d+)\]$"#),
              let match = regex.firstMatch(
                in: name,
                range: NSRange(name.startIndex..., in: name)
              ),
              let baseRange = Range(match.range(at: 1), in: name),
              let indexRange = Range(match.range(at: 2), in: name) else {
            baseName = name
            index = nil
            return
        }
        baseName = String(name[baseRange])
        index = Int(name[indexRange])
    }
}

struct SignalPortGroup: Identifiable, Hashable, Sendable {
    let id: String
    let baseName: String
    let ports: [String]
    let title: String
    let isBus: Bool

    static func make(from portNames: [String]) -> [SignalPortGroup] {
        var order: [String] = []
        var grouped: [String: [SignalPortInfo]] = [:]

        for name in portNames {
            let info = SignalPortInfo(name)
            let key = info.index == nil
                ? "scalar:\(name.lowercased())"
                : "bus:\(info.baseName.lowercased())"
            if grouped[key] == nil { order.append(key) }
            grouped[key, default: []].append(info)
        }

        return order.compactMap { key in
            guard let infos = grouped[key], let first = infos.first else { return nil }
            let isBus = first.index != nil
            let title: String
            if isBus, let start = infos.first?.index, let end = infos.last?.index {
                title = "\(first.baseName)[\(start):\(end)]"
            } else {
                title = first.name
            }
            return SignalPortGroup(
                id: key,
                baseName: first.baseName,
                ports: infos.map(\.name),
                title: title,
                isBus: isBus
            )
        }
    }

    static func sequentialOrder(_ portNames: [String]) -> [String] {
        portNames.sorted { left, right in
            let lhs = SignalPortInfo(left)
            let rhs = SignalPortInfo(right)
            if lhs.baseName.caseInsensitiveCompare(rhs.baseName) == .orderedSame,
               let leftIndex = lhs.index, let rightIndex = rhs.index {
                return leftIndex < rightIndex
            }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

struct PinMappingSnapshot: Codable, Equatable, Sendable {
    let profileID: String
    let topEntity: String
    let mapping: [String: String]
    let clockSignal: String
    let clockPeriod: String
    let updatedAt: Date
}

struct PinMappingPreset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    let profileID: String
    let topEntity: String
    var mapping: [String: String]
    var clockSignal: String
    var clockPeriod: String
    var updatedAt: Date
}

struct PinMappingMergeResult: Equatable, Sendable {
    let mapping: [String: String]
    let reusedCount: Int
    let automaticCount: Int
    let unmappedCount: Int
}

enum PinMappingEngine {
    static func merge(
        ports: [String],
        current: [String: String],
        saved: [String: String],
        automatic: [String: String],
        validPins: Set<String>
    ) -> PinMappingMergeResult {
        let canonicalPins = Dictionary(uniqueKeysWithValues: validPins.map { ($0.lowercased(), $0) })
        let normalizedCurrent = normalized(current)
        let normalizedSaved = normalized(saved)
        let normalizedAutomatic = normalized(automatic)
        var result = Dictionary(uniqueKeysWithValues: ports.map { ($0, "") })
        var usedPins = Set<String>()
        var reused = 0
        var automaticCount = 0

        func apply(_ source: [String: String], countAsAutomatic: Bool) {
            for port in ports where result[port]?.isEmpty == true {
                guard let candidate = source[port.lowercased()],
                      let pin = canonicalPins[candidate.lowercased()],
                      !usedPins.contains(pin.lowercased()) else { continue }
                result[port] = pin
                usedPins.insert(pin.lowercased())
                if countAsAutomatic { automaticCount += 1 } else { reused += 1 }
            }
        }

        apply(normalizedCurrent, countAsAutomatic: false)
        apply(normalizedSaved, countAsAutomatic: false)
        apply(normalizedAutomatic, countAsAutomatic: true)
        let unmapped = result.values.filter(\.isEmpty).count
        return PinMappingMergeResult(
            mapping: result,
            reusedCount: reused,
            automaticCount: automaticCount,
            unmappedCount: unmapped
        )
    }

    static func recommendedCategory(forPort port: String) -> PinCategory? {
        let base = SignalPortInfo(port).baseName.lowercased()
        if ["clk", "clock", "sys_clk"].contains(base) { return .clock }
        if base.hasPrefix("sw") { return .switches }
        if base.contains("button") || base.hasPrefix("btn") || base.hasPrefix("key") { return .buttons }
        if base.hasPrefix("led") { return .leds }
        if base.hasPrefix("seg") { return .sevenSegment }
        if base.hasPrefix("digit") || base.hasPrefix("an") { return .digitSelect }
        if base.hasPrefix("lcd") { return .lcd }
        if base.hasPrefix("uart") { return .uart }
        if base.hasPrefix("wifi") { return .wifi }
        if base.hasPrefix("bt") { return .bluetooth }
        if base.hasPrefix("vga") { return .vga }
        if base.hasPrefix("cam") { return .camera }
        if base.hasPrefix("audio") { return .audio }
        if base.hasPrefix("adc") || base.hasPrefix("dac") { return .converter }
        if base.hasPrefix("ps2") { return .ps2 }
        return nil
    }

    private static func normalized(_ mapping: [String: String]) -> [String: String] {
        var result: [String: String] = [:]
        for (port, pin) in mapping where !pin.isEmpty {
            result[port.lowercased()] = pin
        }
        return result
    }
}

enum PinMappingStore {
    private static let historyKey = "edge.pin-mapping.history.v2"
    private static let presetKey = "edge.pin-mapping.presets.v2"
    private static let recentPinsKey = "edge.pin-mapping.recent-pins.v2"

    static func lastMapping(
        profileID: String,
        topEntity: String,
        defaults: UserDefaults = .standard
    ) -> PinMappingSnapshot? {
        load([PinMappingSnapshot].self, key: historyKey, defaults: defaults)
            .first {
                $0.profileID == profileID
                    && $0.topEntity.caseInsensitiveCompare(topEntity) == .orderedSame
            }
    }

    static func saveLast(
        _ snapshot: PinMappingSnapshot,
        defaults: UserDefaults = .standard
    ) {
        var history = load([PinMappingSnapshot].self, key: historyKey, defaults: defaults)
        history.removeAll {
            $0.profileID == snapshot.profileID
                && $0.topEntity.caseInsensitiveCompare(snapshot.topEntity) == .orderedSame
        }
        history.insert(snapshot, at: 0)
        save(Array(history.prefix(30)), key: historyKey, defaults: defaults)
    }

    static func presets(
        profileID: String,
        defaults: UserDefaults = .standard
    ) -> [PinMappingPreset] {
        load([PinMappingPreset].self, key: presetKey, defaults: defaults)
            .filter { $0.profileID == profileID }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    @discardableResult
    static func savePreset(
        name: String,
        snapshot: PinMappingSnapshot,
        defaults: UserDefaults = .standard
    ) -> PinMappingPreset {
        var all = load([PinMappingPreset].self, key: presetKey, defaults: defaults)
        let cleanedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let existingIndex = all.firstIndex {
            $0.profileID == snapshot.profileID
                && $0.name.caseInsensitiveCompare(cleanedName) == .orderedSame
        }
        let preset = PinMappingPreset(
            id: existingIndex.map { all[$0].id } ?? UUID(),
            name: cleanedName,
            profileID: snapshot.profileID,
            topEntity: snapshot.topEntity,
            mapping: snapshot.mapping,
            clockSignal: snapshot.clockSignal,
            clockPeriod: snapshot.clockPeriod,
            updatedAt: Date()
        )
        if let existingIndex { all[existingIndex] = preset } else { all.append(preset) }
        save(all, key: presetKey, defaults: defaults)
        return preset
    }

    static func deletePreset(_ preset: PinMappingPreset, defaults: UserDefaults = .standard) {
        var all = load([PinMappingPreset].self, key: presetKey, defaults: defaults)
        all.removeAll { $0.id == preset.id }
        save(all, key: presetKey, defaults: defaults)
    }

    static func recentPins(defaults: UserDefaults = .standard) -> [String] {
        defaults.stringArray(forKey: recentPinsKey) ?? []
    }

    static func recordRecentPin(_ pin: String, defaults: UserDefaults = .standard) -> [String] {
        guard !pin.isEmpty else { return recentPins(defaults: defaults) }
        var pins = recentPins(defaults: defaults).filter { $0.caseInsensitiveCompare(pin) != .orderedSame }
        pins.insert(pin, at: 0)
        pins = Array(pins.prefix(10))
        defaults.set(pins, forKey: recentPinsKey)
        return pins
    }

    private static func load<T: Decodable>(
        _ type: T.Type,
        key: String,
        defaults: UserDefaults
    ) -> T where T: ExpressibleByArrayLiteral {
        guard let data = defaults.data(forKey: key),
              let value = try? JSONDecoder().decode(type, from: data) else { return [] }
        return value
    }

    private static func save<T: Encodable>(_ value: T, key: String, defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }
}

enum PinMappingSupportSelfTest {
    static func run() -> Bool {
        let groups = SignalPortGroup.make(from: ["clk", "led[3]", "led[2]", "led[1]", "led[0]"])
        let ordered = SignalPortGroup.sequentialOrder(["led[3]", "led[1]", "led[2]", "led[0]"])
        let merged = PinMappingEngine.merge(
            ports: ["clk", "led[1]", "led[0]", "new_signal"],
            current: ["CLK": "H11", "led[0]": "K12"],
            saved: ["led[1]": "M12"],
            automatic: ["new_signal": "P13"],
            validPins: ["H11", "K12", "M12", "P13"]
        )
        guard groups.count == 2,
              groups[1].title == "led[3:0]",
              ordered == ["led[0]", "led[1]", "led[2]", "led[3]"],
              merged.mapping["clk"] == "H11",
              merged.mapping["led[0]"] == "K12",
              merged.mapping["led[1]"] == "M12",
              merged.mapping["new_signal"] == "P13",
              merged.reusedCount == 3,
              merged.automaticCount == 1,
              merged.unmappedCount == 0,
              PinCategory.classify(label: "LED D10/SEG_A") == .sevenSegment,
              PinCategory.leds.matches(label: "LED D10/SEG_A"),
              PinCategory.lcd.matches(label: "LED D2/LCD_D7"),
              PinCategory.classify(label: "DIGIT1") == .digitSelect,
              PinMappingEngine.recommendedCategory(forPort: "sw[7]") == .switches else {
            return false
        }

        let suiteName = "PinMappingSupportSelfTest.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { return false }
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let snapshot = PinMappingSnapshot(
            profileID: "board",
            topEntity: "Demo",
            mapping: merged.mapping,
            clockSignal: "clk",
            clockPeriod: "20",
            updatedAt: Date()
        )
        PinMappingStore.saveLast(snapshot, defaults: defaults)
        let preset = PinMappingStore.savePreset(name: "Lab 1", snapshot: snapshot, defaults: defaults)
        return PinMappingStore.lastMapping(profileID: "board", topEntity: "demo", defaults: defaults)?.mapping == merged.mapping
            && PinMappingStore.presets(profileID: "board", defaults: defaults) == [preset]
            && PinMappingStore.recordRecentPin("K12", defaults: defaults) == ["K12"]
    }
}
