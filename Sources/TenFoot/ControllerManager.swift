import AppKit
import GameController
import TenFootCore

/// Reads every connected game controller and turns left/right on the d-pad or
/// left stick into focus moves, with hold-to-repeat.
///
/// Works the same for DualShock/DualSense, Xbox, Switch Pro, a Joy-Con pair and a
/// single sideways Joy-Con: all of them are read through GameController's generic
/// `physicalInputProfile`, and GameController already reports a single Joy-Con's
/// stick in its sideways orientation.
///
/// Controllers only deliver input while TenFoot is the frontmost app, so nothing is
/// read once you switch away or quit.
@MainActor
final class ControllerManager: ObservableObject {
    static let keyboardMoveSymbol = "arrow.left.arrow.right"

    /// Symbol for the "Move" hint: the connected controller's own d-pad or stick glyph,
    /// or keyboard arrows when no controller is connected.
    @Published private(set) var moveSymbol = ControllerManager.keyboardMoveSymbol

    private let onMove: (Int) -> Void
    private var repeatFilter = RepeatFilter(initialDelay: Theme.repeatDelay, interval: Theme.repeatInterval)
    private var axes: [ObjectIdentifier: [String: StickAxis]] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(onMove: @escaping (Int) -> Void) {
        self.onMove = onMove

        let names: [Notification.Name] = [.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.controllersChanged() }
            })
        }
        controllersChanged()

        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func controllersChanged() {
        let connected = Set(GCController.controllers().map(ObjectIdentifier.init))
        axes = axes.filter { connected.contains($0.key) }
        moveSymbol = (GCController.current ?? GCController.controllers().first).map(Self.moveSymbol(for:))
            ?? Self.keyboardMoveSymbol
    }

    private func poll() {
        var direction = 0
        if NSApp.isActive {
            for controller in GCController.controllers() {
                let d = horizontalDirection(of: controller)
                if d != 0 {
                    direction = d
                    break
                }
            }
        }
        let move = repeatFilter.update(direction: direction, at: ProcessInfo.processInfo.systemUptime)
        if move != 0 { onMove(move) }
    }

    /// Left/right from the controller's d-pad or left stick (-1, 0 or 1).
    private func horizontalDirection(of controller: GCController) -> Int {
        let id = ObjectIdentifier(controller)
        var controllerAxes = axes[id] ?? [:]
        var direction = 0
        for (name, pad) in Self.navigationPads(of: controller) {
            var axis = controllerAxes[name] ?? StickAxis(pressThreshold: Theme.stickPress,
                                                         releaseThreshold: Theme.stickRelease)
            let d = axis.direction(for: pad.xAxis.value)
            controllerAxes[name] = axis
            if direction == 0 { direction = d }
        }
        axes[id] = controllerAxes
        return direction
    }

    /// The d-pad and the left stick. A single Joy-Con may name its only stick
    /// differently, so every pad counts except a right stick when a left one exists.
    private static func navigationPads(of controller: GCController) -> [(String, GCControllerDirectionPad)] {
        let pads = controller.physicalInputProfile.dpads
        let hasLeftStick = pads[GCInputLeftThumbstick] != nil
        return pads
            .filter { !(hasLeftStick && $0.key == GCInputRightThumbstick) }
            .sorted { $0.key < $1.key }
            .map { ($0.key, $0.value) }
    }

    private static func moveSymbol(for controller: GCController) -> String {
        let pads = controller.physicalInputProfile.dpads
        let element = pads[GCInputDirectionPad] ?? pads[GCInputLeftThumbstick] ?? pads.values.first
        return element?.sfSymbolsName ?? "gamecontroller"
    }
}
