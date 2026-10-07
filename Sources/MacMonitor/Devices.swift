import AppKit
import Combine
import CoreAudio
import Foundation
import IOBluetooth
import IOKit
import SystemBridge

final class AudioController: ObservableObject {
  @Published var apps: [AudioApp] = []
  @Published var devices: [AudioDevice] = []
  @Published var outputID: UInt32 = 0
  @Published var outputName = "System Output"
  @Published var volume = 1.0
  @Published var volumeSupported = false
  @Published var gains: [String: Double] = [:]
  @Published var error: String?
  private var mixers: [String: MMMixer] = [:]
  private var mixerObjects: [String: [UInt32]] = [:]
  private var lastRefresh = Date.distantPast
  func refresh(apps running: [AppStat], force: Bool = false) {
    guard force || Date().timeIntervalSince(lastRefresh) > 2 else { return }
    lastRefresh = Date()
    let previousOutput = outputID
    outputID =
      scalar(
        UInt32(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, as: UInt32.self
      ) ?? 0
    if previousOutput != 0 && previousOutput != outputID { reset() }
    outputName = string(outputID, kAudioObjectPropertyName) ?? "System Output"
    let address = property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
    var a = address
    var settable: DarwinBoolean = false
    volumeSupported =
      AudioObjectIsPropertySettable(outputID, &a, &settable) == noErr && settable.boolValue
    if let v: Float32 = scalar(
      outputID, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
      as: Float32.self)
    {
      volume = Double(v)
    } else if let v: Float32 = scalar(
      outputID, kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput,
      element: 1, as: Float32.self)
    {
      volume = Double(v)
      a.mElement = 1
      volumeSupported =
        AudioObjectIsPropertySettable(outputID, &a, &settable) == noErr && settable.boolValue
    }
    if let mute: UInt32 = scalar(
      outputID, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, as: UInt32.self),
      mute != 0
    {
      volume = 0
    }
    devices = objects(UInt32(kAudioObjectSystemObject), kAudioHardwarePropertyDevices).compactMap {
      id in
      var address = property(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
      var bytes: UInt32 = 0
      guard AudioObjectGetPropertyDataSize(id, &address, 0, nil, &bytes) == noErr, bytes > 0,
        string(id, kAudioObjectPropertyName)?.contains("Mac Monitor") != true
      else { return nil }
      return AudioDevice(id: id, name: string(id, kAudioObjectPropertyName) ?? "Output")
    }
    var raw = [MMAudioProcess](repeating: MMAudioProcess(), count: 512)
    let n = mm_audio_processes(&raw, Int32(raw.count))
    var groups: [String: AudioApp] = [:]
    for p in raw.prefix(Int(n)) where p.pid != getpid() {
      let app = running.first { $0.processes.contains(where: { $0.pid == p.pid }) }
      let bundle = tupleString(p.bundle)
      let id = app?.id ?? (bundle.isEmpty ? "audio:\(p.pid)" : bundle)
      let name =
        app?.name
        ?? (bundle.isEmpty ? "Process \(p.pid)" : bundle.components(separatedBy: ".").last!)
      var row =
        groups[id] ?? AudioApp(id: id, name: name, icon: app?.icon, objects: [], playing: false)
      row.objects.append(p.object)
      row.playing = row.playing || p.playing
      groups[id] = row
    }
    apps = groups.values.sorted { $0.playing != $1.playing ? $0.playing : $0.name < $1.name }
    for (id, mixer) in mixers {
      guard let app = groups[id], app.objects.sorted() == mixerObjects[id]?.sorted() else {
        mm_mixer_destroy(mixer)
        mixers[id] = nil
        mixerObjects[id] = nil
        if let app = groups[id], let gain = gains[id], gain < 1 { setGain(app, gain) }
        continue
      }
    }
  }
  private func property(
    _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0
  ) -> AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
  }
  private func scalar<T>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0,
    as type: T.Type
  ) -> T? {
    var address = property(selector, scope: scope, element: element)
    var size = UInt32(MemoryLayout<T>.size)
    let pointer = UnsafeMutableRawPointer.allocate(
      byteCount: Int(size), alignment: MemoryLayout<T>.alignment)
    defer { pointer.deallocate() }
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, pointer) == noErr else {
      return nil
    }
    return pointer.load(as: T.self)
  }
  private func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
    var a = property(selector)
    var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    var value: Unmanaged<CFString>?
    guard AudioObjectGetPropertyData(object, &a, 0, nil, &size, &value) == noErr, let value else {
      return nil
    }
    return value.takeRetainedValue() as String
  }
  private func objects(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector)
    -> [AudioObjectID]
  {
    var a = property(selector)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &a, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard !ids.isEmpty, AudioObjectGetPropertyData(object, &a, 0, nil, &size, &ids) == noErr else {
      return []
    }
    return ids
  }
  func setVolume(_ v: Double) {
    var value = Float32(v)
    var a = property(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput)
    var status = AudioObjectSetPropertyData(
      outputID, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    if status != noErr {
      for channel: UInt32 in [1, 2] {
        a.mElement = channel
        status = AudioObjectSetPropertyData(outputID, &a, 0, nil, 4, &value)
      }
    }
    var mute: UInt32 = v == 0 ? 1 : 0
    a = property(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput)
    AudioObjectSetPropertyData(outputID, &a, 0, nil, 4, &mute)
    if status == noErr { volume = v } else { error = "This output device manages its own volume." }
  }
  func selectOutput(_ id: AudioObjectID) {
    var a = property(kAudioHardwarePropertyDefaultOutputDevice)
    var id = id
    let status = AudioObjectSetPropertyData(UInt32(kAudioObjectSystemObject), &a, 0, nil, 4, &id)
    if status != noErr {
      error = "Could not change the output device (\(status))."
    } else {
      reset()
      outputID = id
    }
  }
  func setGain(_ app: AudioApp, _ gain: Double) {
    if gain >= 0.999 {
      if let mixer = mixers.removeValue(forKey: app.id) { mm_mixer_destroy(mixer) }
      gains[app.id] = 1
      mixerObjects[app.id] = nil
      return
    }
    if let mixer = mixers[app.id] {
      mm_mixer_gain(mixer, Float(gain))
      gains[app.id] = gain
      return
    }
    var status: Int32 = 0
    let mixer = app.objects.withUnsafeBufferPointer {
      mm_mixer_create($0.baseAddress, Int32($0.count), Float(gain), &status)
    }
    if let mixer {
      mixers[app.id] = mixer
      mixerObjects[app.id] = app.objects
      gains[app.id] = gain
    } else {
      error =
        "Audio mixing could not start (\(status)). Allow Mac Monitor in System Settings → Privacy & Security → Screen & System Audio Recording, then relaunch."
    }
  }
  func reset() {
    for mixer in mixers.values { mm_mixer_destroy(mixer) }
    mixers.removeAll()
    mixerObjects.removeAll()
    gains.removeAll()
  }
  deinit { for mixer in mixers.values { mm_mixer_destroy(mixer) } }
}

final class BluetoothController: ObservableObject {
  @Published var devices: [BluetoothStat] = []
  @Published var loading = false
  @Published var enabled = false
  @Published var error: String?
  func refresh() {
    guard !loading else { return }
    enabled = true
    loading = true
    DispatchQueue.global(qos: .utility).async {
      let text = runCommand(
        "/usr/sbin/system_profiler", ["SPBluetoothDataType", "-json", "-detailLevel", "mini"],
        timeout: 12)
      var result: [BluetoothStat] = []
      if let data = text.data(using: .utf8),
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let roots = json["SPBluetoothDataType"] as? [[String: Any]]
      {
        for root in roots {
          for key in ["device_connected", "device_not_connected"] {
            let connected = key == "device_connected"
            for entry in root[key] as? [[String: Any]] ?? [] {
              for (name, raw) in entry {
                guard let props = raw as? [String: Any] else { continue }
                let id = props["device_address"] as? String ?? name
                let minor =
                  (props["device_minorType"] as? String ?? props["device_minor_type"] as? String
                  ?? "Device").replacingOccurrences(of: "Device_", with: "").capitalized
                var levels: [(String, Int)] = []
                for (k, v) in props where k.lowercased().contains("battery") {
                  let text = String(describing: v).filter(\.isNumber)
                  if let n = Int(text), n <= 100 {
                    let label =
                      k.lowercased().contains("left")
                      ? "Left"
                      : k.lowercased().contains("right")
                        ? "Right" : k.lowercased().contains("case") ? "Case" : "Battery"
                    levels.append((label, n))
                  }
                }
                levels.sort { $0.0 < $1.0 }
                result.append(
                  BluetoothStat(
                    id: id, name: name, kind: minor, connected: connected, levels: levels))
              }
            }
          }
        }
      }
      // HID devices sometimes publish battery only through IORegistry.
      var iterator: io_iterator_t = 0
      if IOServiceGetMatchingServices(
        kIOMainPortDefault, IOServiceMatching("IOHIDDevice"), &iterator) == KERN_SUCCESS
      {
        while case let object = IOIteratorNext(iterator), object != 0 {
          let p = registryProperties(object)
          IOObjectRelease(object)
          if let battery = (p["BatteryPercent"] as? NSNumber)?.intValue,
            let name = p["Product"] as? String
          {
            if let index = result.firstIndex(where: { $0.name == name }) {
              if result[index].levels.isEmpty { result[index].levels = [("Battery", battery)] }
            } else {
              result.append(
                BluetoothStat(
                  id: name, name: name,
                  kind: name.contains("Keyboard")
                    ? "Keyboard" : name.contains("Trackpad") ? "Trackpad" : "Mouse",
                  connected: true, levels: [("Battery", battery)]))
            }
          }
        }
        IOObjectRelease(iterator)
      }
      DispatchQueue.main.async {
        self.devices = result.sorted {
          $0.connected != $1.connected ? $0.connected : $0.name < $1.name
        }
        self.loading = false
        if text.isEmpty {
          self.error =
            "Bluetooth information is unavailable. Allow Bluetooth access in System Settings and refresh."
        }
      }
    }
  }
}
