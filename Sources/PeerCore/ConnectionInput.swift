import Foundation

/// Manual-connection input. Trims whitespace, accepts a pasted "host:port" or "[IPv6]:port" line
/// (the format Copy connection information produces), and rejects ports outside 1–65535.
public enum ManualEndpoint {
    public static func parse(host rawHost: String, port rawPort: String) -> (host: String, port: UInt16)? {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines)
        var port = rawPort.trimmingCharacters(in: .whitespacesAndNewlines)
        if port.isEmpty {
            if host.hasPrefix("["), let close = host.lastIndex(of: "]"), host[host.index(after: close)...].hasPrefix(":") {
                port = String(host[host.index(close, offsetBy: 2)...]); host = String(host[host.index(after: host.startIndex)..<close])
            } else if host.filter({ $0 == ":" }).count == 1, let colon = host.firstIndex(of: ":") {
                port = String(host[host.index(after: colon)...]); host = String(host[..<colon])
            }
        }
        guard !host.isEmpty, !host.contains(where: \.isWhitespace), let value = UInt16(port), value > 0 else { return nil }
        return (host, value)
    }
}

/// Display-only grouping of the six-digit pairing code; verification always uses the original value.
public enum PairingCodeDisplay {
    public static func grouped(_ code: String) -> String {
        guard code.count == 6, code.allSatisfy(\.isASCII), code.allSatisfy(\.isNumber) else { return code }
        return String(code.prefix(3)) + " " + String(code.suffix(3))
    }
    /// Digit-by-digit reading for VoiceOver, so the code is not read as two numbers.
    public static func spoken(_ code: String) -> String { code.map(String.init).joined(separator: " ") }
}
