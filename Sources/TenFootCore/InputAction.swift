/// What the user asked for, from a controller or the keyboard.
public enum InputAction: Sendable, Equatable {
    case left, right, up, down
    case confirm // A on the controller, Return on the keyboard
    case back    // B on the controller, Esc on the keyboard
}
