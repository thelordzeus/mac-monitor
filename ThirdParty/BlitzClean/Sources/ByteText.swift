import Foundation

enum ByteText {
  static func compact(_ bytes: UInt64) -> String {
    format((bytes: bytes, fractionDigits: 0))
  }

  static func full(_ bytes: UInt64) -> String {
    format((bytes: bytes, fractionDigits: 1))
  }

  private static func format(_ input: (bytes: UInt64, fractionDigits: Int)) -> String {
    let gigabytes = Double(input.bytes) / 1_000_000_000

    if gigabytes >= 1 {
      return gigabytes.formatted(
        .number.precision(.fractionLength(input.fractionDigits))
      ) + " GB"
    }

    if input.bytes < 1_000 { return "\(input.bytes) B" }
    if input.bytes < 1_000_000 {
      return (Double(input.bytes) / 1_000).formatted(
        .number.precision(.fractionLength(input.fractionDigits))
      ) + " KB"
    }
    let megabytes = Double(input.bytes) / 1_000_000
    return megabytes.formatted(
      .number.precision(.fractionLength(input.fractionDigits))
    ) + " MB"
  }
}


/// RAM uses the same binary units as the host monitoring tabs.
enum MemoryByteText {
  static func full(_ bytes: UInt64) -> String { format(bytes, digits: 2) }
  static func compact(_ bytes: UInt64) -> String { format(bytes, digits: 0) }
  private static func format(_ bytes: UInt64, digits: Int) -> String {
    let value = Double(bytes)
    if value >= 1_073_741_824 { return String(format: "%.*f GB", digits, value / 1_073_741_824) }
    if value >= 1_048_576 { return String(format: "%.0f MB", value / 1_048_576) }
    if value >= 1_024 { return String(format: "%.0f kB", value / 1_024) }
    return "\(bytes) B"
  }
}
