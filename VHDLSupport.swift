import Foundation

struct BoardProfile: Decodable, Identifiable, Sendable {
    let schemaVersion: Int
    let profileID: String
    let displayName: String
    let fpgaPart: String
    let toolchain: String
    let defaultClock: DefaultClock
    let pins: [String: String]

    var id: String { profileID }

    struct DefaultClock: Decodable, Sendable {
        let signal: String
        let periodNS: Double

        enum CodingKeys: String, CodingKey {
            case signal
            case periodNS = "period_ns"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case profileID = "profile_id"
        case displayName = "display_name"
        case fpgaPart = "fpga_part"
        case toolchain
        case defaultClock = "default_clock"
        case pins
    }
}

struct PinOption: Identifiable, Hashable, Sendable {
    let pin: String
    let label: String
    var id: String { pin }
    var display: String { "\(label)  •  \(pin)" }
}

struct VHDLAnalysis: Sendable {
    let entityNames: [String]
    let topEntity: String
    let ports: [String]
}

enum VHDLPortParser {
    static func analyze(paths: [String], preferredTop: String?) -> VHDLAnalysis {
        let text = paths.compactMap {
            try? String(contentsOfFile: $0, encoding: .utf8)
        }.joined(separator: "\n")
        let entities = entityNames(inText: text)
        let requested = preferredTop?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let selectedTop: String
        if let matching = entities.first(where: {
            $0.caseInsensitiveCompare(requested) == .orderedSame
        }) {
            selectedTop = matching
        } else {
            selectedTop = entities.last ?? requested
        }
        return VHDLAnalysis(
            entityNames: entities,
            topEntity: selectedTop,
            ports: ports(inText: text, topEntity: selectedTop)
        )
    }

    static func entityNames(in files: [URL]) -> [String] {
        entityNames(inText: combinedText(files: files))
    }

    static func ports(in files: [URL], topEntity: String) -> [String] {
        ports(inText: combinedText(files: files), topEntity: topEntity)
    }

    private static func entityNames(inText text: String) -> [String] {
        let matches = captures(
            pattern: #"(?i)\bentity\s+([A-Za-z][A-Za-z0-9_]*)\s+is\b"#,
            text: text
        )
        var seen = Set<String>()
        return matches.filter { seen.insert($0.lowercased()).inserted }
    }

    private static func ports(inText source: String, topEntity: String) -> [String] {
        guard !topEntity.isEmpty else { return [] }
        let text = stripComments(source)
        let escapedTop = NSRegularExpression.escapedPattern(for: topEntity)
        let entityPattern = "(?is)\\bentity\\s+\(escapedTop)\\s+is\\b(?<body>.*?)\\bend(?:\\s+(?:entity\\s+)?\(escapedTop))?\\s*;"
        guard let entityBody = namedCapture(
            pattern: entityPattern,
            name: "body",
            text: text
        ), let portBlock = balancedPortBlock(in: entityBody) else {
            return []
        }

        var ports: [String] = []
        let declarationPattern = #"(?is)^([A-Za-z][A-Za-z0-9_]*(?:\s*,\s*[A-Za-z][A-Za-z0-9_]*)*)\s*:\s*(?:in|out|inout|buffer)\s+(.+)$"#
        let declarationRegex = try? NSRegularExpression(pattern: declarationPattern)
        let rangeRegex = try? NSRegularExpression(
            pattern: #"\(\s*(\d+)\s*(downto|to)\s*(\d+)\s*\)"#,
            options: [.caseInsensitive]
        )

        for rawDeclaration in portBlock.components(separatedBy: ";") {
            let declaration = rawDeclaration.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !declaration.isEmpty,
                  let match = declarationRegex?.firstMatch(
                    in: declaration,
                    range: NSRange(declaration.startIndex..., in: declaration)
                  ),
                  let namesRange = Range(match.range(at: 1), in: declaration),
                  let typeRange = Range(match.range(at: 2), in: declaration) else { continue }

            let names = declaration[namesRange].components(separatedBy: ",").map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let typeText = String(declaration[typeRange])
            let typeNSRange = NSRange(typeText.startIndex..., in: typeText)
            if let rangeMatch = rangeRegex?.firstMatch(in: typeText, range: typeNSRange),
               let leftRange = Range(rangeMatch.range(at: 1), in: typeText),
               let directionRange = Range(rangeMatch.range(at: 2), in: typeText),
               let rightRange = Range(rangeMatch.range(at: 3), in: typeText),
               let left = Int(typeText[leftRange]),
               let right = Int(typeText[rightRange]) {
                let descending = typeText[directionRange].lowercased() == "downto"
                for name in names {
                    if descending, left >= right {
                        for index in stride(from: left, through: right, by: -1) {
                            ports.append("\(name)[\(index)]")
                        }
                    } else if !descending, left <= right {
                        for index in left...right {
                            ports.append("\(name)[\(index)]")
                        }
                    }
                }
            } else {
                ports.append(contentsOf: names)
            }
        }
        return ports
    }

    private static func combinedText(files: [URL]) -> String {
        files.compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }

    private static func stripComments(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"--[^\r\n]*"#,
            with: "",
            options: .regularExpression
        )
    }

    private static func captures(pattern: String, text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(
            in: text,
            range: NSRange(text.startIndex..., in: text)
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func namedCapture(
        pattern: String,
        name: String,
        text: String
    ) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let range = Range(match.range(withName: name), in: text) else { return nil }
        return String(text[range])
    }

    private static func balancedPortBlock(in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?i)\bport\s*\("#),
              let match = regex.firstMatch(
                in: text,
                range: NSRange(text.startIndex..., in: text)
              ),
              let matchRange = Range(match.range, in: text) else { return nil }
        let opening = text.index(before: matchRange.upperBound)
        var depth = 0
        var cursor = opening
        while cursor < text.endIndex {
            if text[cursor] == "(" { depth += 1 }
            if text[cursor] == ")" {
                depth -= 1
                if depth == 0 {
                    return String(text[text.index(after: opening)..<cursor])
                }
            }
            cursor = text.index(after: cursor)
        }
        return nil
    }
}

enum VHDLSupportSelfTest {
    static func run() -> Bool {
        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("edge-local-parser-\(UUID().uuidString).vhd")
        let source = """
        entity demo_top is
          port (
            clk : in std_logic;
            sw  : in std_logic_vector(1 downto 0);
            led : out std_logic
          );
        end demo_top;
        """
        do {
            try source.write(to: temporary, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: temporary) }
            let analysis = VHDLPortParser.analyze(
                paths: [temporary.path],
                preferredTop: "demo_top"
            )
            return analysis.entityNames == ["demo_top"]
                && analysis.topEntity == "demo_top"
                && analysis.ports == ["clk", "sw[1]", "sw[0]", "led"]
        } catch {
            return false
        }
    }
}
