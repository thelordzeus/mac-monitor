import Darwin
import Foundation

public struct NetworkReport: Sendable {
  public let date: Date, host: String, addresses: String, latency: Double?, loss: Double?,
    https: String, pingOutput: String
}
public enum NetworkDiagnostics {
  public static func validHost(_ text: String) -> Bool {
    guard !text.isEmpty, text.count <= 253, !text.hasPrefix("-") else { return false }
    var ipv6 = in6_addr()
    if inet_pton(AF_INET6, text, &ipv6) == 1 { return true }
    return text.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { part in
      !part.isEmpty && part.count <= 63 && part.first != "-" && part.last != "-"
        && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }
  }
  public static func pingStatistics(_ text: String) -> (loss: Double?, latency: Double?) {
    func number(_ pattern: String) -> Double? {
      guard let regex = try? NSRegularExpression(pattern: pattern),
        let result = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
        let range = Range(result.range(at: 1), in: text)
      else { return nil }
      return Double(text[range])
    }
    return (
      number("([0-9.]+)% packet loss"), number("(?:round-trip|round trip).*?= [0-9.]+/([0-9.]+)/")
    )
  }
  public static func run(host: String) async throws -> NetworkReport {
    guard validHost(host) else {
      throw NSError(
        domain: "NetworkDiagnostics", code: 1,
        userInfo: [
          NSLocalizedDescriptionKey:
            "Enter a hostname or IP address without a URL, spaces or options."
        ])
    }
    async let ping = Task.detached(priority: .utility) {
      command(
        host.contains(":") ? "/sbin/ping6" : "/sbin/ping", ["-n", "-c", "5", host], timeout: 12)
    }.value
    async let dns = Task.detached(priority: .utility) {
      command("/usr/bin/dig", ["+time=2", "+tries=1", "+short", host], timeout: 5)
    }.value
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 8
    config.timeoutIntervalForResource = 10
    let session = URLSession(configuration: config)
    defer { session.invalidateAndCancel() }
    let https: String
    do {
      let (_, response) = try await session.data(
        from: URL(string: "https://www.apple.com/library/test/success.html")!)
      https =
        (response as? HTTPURLResponse).map { "Apple connectivity endpoint: HTTP \($0.statusCode)" }
        ?? "HTTPS response received"
    } catch { https = "HTTPS failed: \(error.localizedDescription)" }
    let p = await ping
    let d = await dns
    let stats = pingStatistics(p)
    return .init(
      date: .now, host: host, addresses: d.trimmingCharacters(in: .whitespacesAndNewlines),
      latency: stats.latency, loss: stats.loss, https: https, pingOutput: p)
  }
  private static func command(_ executable: String, _ arguments: [String], timeout: Double)
    -> String
  {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = pipe
    process.standardError = pipe
    do { try process.run() } catch { return error.localizedDescription }
    let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
    let killTask = DispatchWorkItem {
      if process.isRunning { kill(process.processIdentifier, SIGKILL) }
    }
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: stop)
    DispatchQueue.global().asyncAfter(deadline: .now() + timeout + 1, execute: killTask)
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    stop.cancel()
    killTask.cancel()
    return String(decoding: data.prefix(12000), as: UTF8.self)
  }
}
