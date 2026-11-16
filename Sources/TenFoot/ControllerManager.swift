import AppKit
import GameController
import TenFootCore

/// Reads every connected game controller and turns it into `InputAction`s:
/// the d-pad or left stick moves (with hold-to-repeat), A confirms, B goes back.
///
/// Works the same for DualShock/DualSense, Xbox, Switch Pro, a Joy-Con pair and a
/// single sideways Joy-Con: all of them are read through GameController's generic
/// `physicalInputProfile`, and GameController already reports a single Joy-Con's
/// stick in its sideways orientation. "A" and "B" are each controller's own
/// confirm and back buttons (on Nintendo controllers A is the right-hand button).
///
/// Controllers only deliver input while TenFoot is the frontmost app, so nothing is
/// read once you switch away or quit.
@MainActor
final class ControllerManager: ObservableObject {
    static let keyboardMoveSymbol = "arrow.up.and.down.and.arrow.left.and.right"
    static let keyboardConfirmSymbol = "return"
    static let keyboardBackSymbol = "escape"

    /// Glyphs for the hint bar: the connected controller's own d-pad, A and B,
    /// or keyboard keys when no controller is connected.
    @Published private(set) var moveSymbol = ControllerManager.keyboardMoveSymbol
    @Published private(set) var confirmSymbol = ControllerManager.keyboardConfirmSymbol
    @Published private(set) var backSymbol = ControllerManager.keyboardBackSymbol

    private let onAction: (InputAction) -> Void
    private var horizontal = RepeatFilter(initialDelay: Theme.repeatDelay, interval: Theme.repeatInterval)
    private var vertical = RepeatFilter(initialDelay: Theme.repeatDelay, interval: Theme.repeatInterval)
    private var axes: [ObjectIdentifier: [String: (x: StickAxis, y: StickAxis)]] = [:]
    private var buttonsDown: [ObjectIdentifier: Set<String>] = [:]
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?

    init(onAction: @escaping (InputAction) -> Void) {
        self.onAction = onAction

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
        buttonsDown = buttonsDown.filter { connected.contains($0.key) }

        let controller = GCController.current ?? GCController.controllers().first
        let profile = controller?.physicalInputProfile
        let pads = profile?.dpads ?? [:]
        let pad = pads[GCInputDirectionPad] ?? pads[GCInputLeftThumbstick] ?? pads.values.first
        moveSymbol = controller == nil ? Self.keyboardMoveSymbol : (pad?.sfSymbolsName ?? "gamecontroller")
        confirmSymbol = profile?.buttons[GCInputButtonA]?.sfSymbolsName ?? Self.keyboardConfirmSymbol
        backSymbol = profile?.buttons[GCInputButtonB]?.sfSymbolsName ?? Self.keyboardBackSymbol
    }

    private func poll() {
        // Button and stick state is always tracked, so a button that is already held
        // when TenFoot comes back to the front (or a file picker closes) doesn't fire.
        let accepting = NSApp.isActive && NSApp.modalWindow == nil
        var x = 0, y = 0
        var pressed: [InputAction] = []

        for controller in GCController.controllers() {
            let (dx, dy) = direction(of: controller)
            if x == 0 && y == 0 { (x, y) = (dx, dy) }
            pressed += newlyPressedButtons(of: controller)
        }
        if !accepting {
            (x, y) = (0, 0)
            pressed = []
        }

        // Horizontal wins when both are held, so a diagonal stick still moves along the row.
        let now = ProcessInfo.processInfo.systemUptime
        let moveX = horizontal.update(direction: x, at: now)
        let moveY = vertical.update(direction: x == 0 ? y : 0, at: now)
        if moveX != 0 { onAction(moveX < 0 ? .left : .right) }
        if moveY != 0 { onAction(moveY > 0 ? .up : .down) }
        pressed.forEach(onAction)
    }

    /// Direction from the controller's d-pad or left stick: x is -1 left / 1 right,
    /// y is 1 up / -1 down.
    private func direction(of controller: GCController) -> (Int, Int) {
        let id = ObjectIdentifier(controller)
        var controllerAxes = axes[id] ?? [:]
        var x = 0, y = 0
        for (name, pad) in Self.navigationPads(of: controller) {
            var axis = controllerAxes[name] ?? (StickAxis(pressThreshold: Theme.stickPress, releaseThreshold: Theme.stickRelease),
                                                StickAxis(pressThreshold: Theme.stickPress, releaseThreshold: Theme.stickRelease))
            let dx = axis.x.direction(for: pad.xAxis.value)
            let dy = axis.y.direction(for: pad.yAxis.value)
            controllerAxes[name] = axis
            if x == 0 && y == 0 { (x, y) = (dx, dy) }
        }
        axes[id] = controllerAxes
        return (x, y)
    }

    /// Confirm/back for buttons that went down since the last poll.
    private func newlyPressedButtons(of controller: GCController) -> [InputAction] {
        let id = ObjectIdentifier(controller)
        let buttons = controller.physicalInputProfile.buttons
        let wasDown = buttonsDown[id] ?? []
        var down: Set<String> = []
        var actions: [InputAction] = []
        for (name, action) in [(GCInputButtonA, InputAction.confirm), (GCInputButtonB, .back)] {
            guard buttons[name]?.isPressed == true else { continue }
            down.insert(name)
            if !wasDown.contains(name) { actions.append(action) }
        }
        buttonsDown[id] = down
        return actions
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
}
