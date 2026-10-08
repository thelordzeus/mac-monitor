import Foundation
import Testing

@testable import PulseCore

struct ObservationTests {
  private func sample(
    _ time: Double, duration: Double = 2, cpu: Double = 80, memory: Double = 100,
    identity: String = "one", disk: Double? = 5e9, pressure: Int? = 0, apps: Bool = true
  ) -> ResourceObservation {
    .init(
      date: Date(timeIntervalSince1970: time), duration: duration, cpu: cpu, diskFree: disk,
      pressure: pressure, swap: 0, temperature: nil,
      apps: apps
        ? [
          .init(
            id: "app", name: "Test App", identity: identity, cpu: cpu, memory: memory, write: 120e6,
            network: .nan)
        ] : [])
  }
  @Test func sustainedRulesNeedContinuousObservedTimeAndRespectCooldown() {
    var engine = ObservationEngine()
    let rules = [AlertRule(metric: .cpu, threshold: 70, seconds: 6)]
    #expect(engine.observe(sample(100), rules: rules).isEmpty)
    #expect(engine.observe(sample(102), rules: rules).isEmpty)
    #expect(engine.observe(sample(104), rules: rules).count == 1)
    #expect(engine.findings.first?.appID == "app")
    #expect(engine.observe(sample(106), rules: rules).isEmpty)
    #expect(engine.findings.count == 1)
    _ = engine.observe(sample(108, cpu: 20), rules: rules)
    #expect(engine.findings.isEmpty)
    _ = engine.observe(sample(110), rules: rules)
    #expect(engine.findings.isEmpty)
  }
  @Test func sleepPauseAndRestartResetElapsedTime() {
    let rule = [AlertRule(metric: .cpu, seconds: 6)]
    var engine = ObservationEngine()
    _ = engine.observe(sample(100), rules: rule)
    _ = engine.observe(sample(102), rules: rule)
    #expect(engine.observe(sample(200), rules: rule).isEmpty)
    #expect(engine.observe(sample(202, duration: 0), rules: rule).isEmpty)
    _ = engine.observe(sample(204), rules: rule)
    _ = engine.observe(sample(206), rules: rule)
    #expect(engine.observe(sample(208, identity: "restarted"), rules: rule).isEmpty)
    #expect(engine.findings.isEmpty)
  }
  @Test func unknownSensorsAndAbsentAppsCannotTriggerRules() {
    var engine = ObservationEngine()
    let rules = [
      AlertRule(metric: .temperature, seconds: 0), AlertRule(metric: .network, seconds: 0),
      AlertRule(metric: .diskFree, seconds: 0), AlertRule(metric: .pressure, seconds: 0),
    ]
    #expect(engine.observe(sample(100, disk: nil, pressure: nil), rules: rules).isEmpty)
    #expect(
      engine.observe(
        sample(102, cpu: 100, disk: nil, pressure: nil, apps: false),
        rules: [AlertRule(metric: .cpu, seconds: 0)]
      ).isEmpty)
  }
  @Test func memoryGrowthUsesTenMinutesAndNewProcessBaseline() {
    var engine = ObservationEngine()
    let rules = [AlertRule(metric: .memoryGrowth, threshold: 100, seconds: 0)]
    var alerts: [ResourceFinding] = []
    for second in stride(from: 100, through: 700, by: 2) {
      alerts += engine.observe(
        sample(Double(second), memory: second == 700 ? 200 * 1_048_576 : 10 * 1_048_576),
        rules: rules)
    }
    #expect(alerts.count == 1)
    #expect(alerts.first?.metric == .memoryGrowth)
    #expect(
      engine.observe(sample(702, memory: 400 * 1_048_576, identity: "new"), rules: rules).isEmpty)
    #expect(engine.findings.isEmpty)
  }
  @Test func appSelectionDisabledRulesAndLowSpaceDirection() {
    var engine = ObservationEngine()
    let rules = [
      AlertRule(metric: .cpu, seconds: 0, appID: "different"),
      AlertRule(metric: .diskWrite, seconds: 0, enabled: false),
      AlertRule(metric: .diskFree, threshold: 10, seconds: 0),
    ]
    #expect(engine.observe(sample(100), rules: rules).map(\.metric) == [.diskFree])
    _ = engine.observe(sample(102, disk: 15e9), rules: rules)
    #expect(engine.findings.isEmpty)
  }
  @Test func quietHoursHandleMidnightAndKeepDaytimeOpen() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let hours = QuietHours(enabled: true, startHour: 22, endHour: 8)
    for hour in [22, 23, 0, 7] {
      #expect(hours.contains(Date(timeIntervalSince1970: Double(hour * 3600)), calendar: calendar))
    }
    for hour in [8, 12, 21] {
      #expect(!hours.contains(Date(timeIntervalSince1970: Double(hour * 3600)), calendar: calendar))
    }
    #expect(!QuietHours().contains(.now))
    #expect(QuietHours(enabled: true, startHour: 8, endHour: 8).contains(.now))
  }
}
