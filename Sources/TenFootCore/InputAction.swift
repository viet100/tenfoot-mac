/// What the user asked for, from a controller or the keyboard.
public enum InputAction: Sendable, Equatable {
    case left, right, up, down
    case confirm // A on the controller, Return on the keyboard
    case back    // B on the controller, Esc on the keyboard
    case close   // X on the controller, X on the keyboard: close the running game
    case home    // Home, or − and + together: back to TenFoot from a game
    case options // Y on the controller, Y on the keyboard: the focused game's options
}
