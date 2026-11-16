import CoreWLAN
import IOKit.ps
import SwiftUI

/// Battery and Wi‑Fi readings for the status bar, refreshed every few seconds.
@MainActor
final class StatusModel: ObservableObject {
    struct Battery: Equatable {
        var percent: Int
        var charging: Bool
    }

    struct WiFi: Equatable {
        var poweredOn: Bool
        var connected: Bool
        var name: String?    // nil unless macOS grants Location access, which TenFoot doesn't request
        var strength: Double // 0...1
    }

    @Published private(set) var battery: Battery?
    @Published private(set) var wifi: WiFi?
    /// Set only for CI snapshots, so the clock doesn't change between renders.
    let fixedDate: Date?

    private var timer: Timer?

    init() {
        fixedDate = nil
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: Theme.statusRefreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    /// Fixed values used when rendering CI snapshots (the CI machine has no battery or Wi‑Fi).
    init(sample: Void) {
        battery = Battery(percent: 82, charging: false)
        wifi = WiFi(poweredOn: true, connected: true, name: "Home", strength: 1)
        fixedDate = Calendar.current.date(bySettingHour: 21, minute: 41, second: 0, of: Date())
    }

    func refresh() {
        battery = Self.readBattery()
        wifi = Self.readWiFi()
    }

    private static func readBattery() -> Battery? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            let charging = description[kIOPSIsChargingKey] as? Bool ?? false
            return Battery(percent: min(100, current * 100 / max), charging: charging)
        }
        return nil // desktop Macs have no battery; the item is hidden
    }

    private static func readWiFi() -> WiFi? {
        guard let interface = CWWiFiClient.shared().interface() else { return nil }
        let poweredOn = interface.powerOn()
        let rssi = interface.rssiValue() // 0 when not associated
        let connected = poweredOn && rssi != 0
        // Map roughly -90 dBm (weak) ... -50 dBm (strong) to 0...1.
        let strength = connected ? min(1, max(0, Double(rssi + 90) / 40)) : 0
        return WiFi(poweredOn: poweredOn, connected: connected, name: interface.ssid(), strength: strength)
    }
}

/// Battery, Wi‑Fi and time on one line, top right.
struct StatusBar: View {
    @ObservedObject var model: StatusModel
    let unit: CGFloat

    var body: some View {
        HStack(spacing: unit * Theme.statusItemSpacing) {
            if let battery = model.battery {
                item(symbol: batterySymbol(battery), label: "\(battery.percent)%")
            }
            if let wifi = model.wifi {
                wifiItem(wifi)
            }
            clock
        }
        .font(.system(size: unit * Theme.statusSize, weight: .medium))
        .monospacedDigit()
        .foregroundStyle(.white)
        .padding(.horizontal, unit * 0.03)
        .padding(.vertical, unit * 0.016)
        .glassEffect(.regular, in: Capsule())
    }

    @ViewBuilder
    private var clock: some View {
        if let fixed = model.fixedDate {
            item(symbol: "clock", label: fixed.formatted(date: .omitted, time: .shortened))
        } else {
            TimelineView(.everyMinute) { context in
                item(symbol: "clock", label: context.date.formatted(date: .omitted, time: .shortened))
            }
        }
    }

    private func wifiItem(_ wifi: StatusModel.WiFi) -> some View {
        HStack(spacing: unit * 0.01) {
            if wifi.connected {
                Image(systemName: "wifi", variableValue: wifi.strength)
            } else {
                Image(systemName: "wifi.slash")
            }
            Text(wifi.connected ? (wifi.name ?? "Wi‑Fi") : (wifi.poweredOn ? "Not Connected" : "Wi‑Fi Off"))
        }
    }

    private func item(symbol: String, label: String) -> some View {
        HStack(spacing: unit * 0.01) {
            Image(systemName: symbol)
            Text(label)
        }
    }

    private func batterySymbol(_ battery: StatusModel.Battery) -> String {
        if battery.charging { return "battery.100percent.bolt" }
        switch battery.percent {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }
}
