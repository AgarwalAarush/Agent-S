import Foundation
import CoreGraphics
import AppKit

/// Executor that converts Action enum to CGEvent commands
class CGEventExecutor {
    
    /// Execute a click action at the specified coordinates
    /// - Parameters:
    ///   - point: Click location
    ///   - numClicks: Number of clicks
    ///   - buttonType: Mouse button type ("left", "right", "middle")
    static func click(point: CGPoint, numClicks: Int = 1, buttonType: String) {
        let mouseButton: CGMouseButton
        switch buttonType.lowercased() {
        case "right":
            mouseButton = .right
        case "middle":
            mouseButton = .center
        default:
            mouseButton = .left
        }
        
        for _ in 0..<numClicks {
            // Mouse down
            let downEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseButton == .left ? .leftMouseDown : mouseButton == .right ? .rightMouseDown : .otherMouseDown,
                mouseCursorPosition: point,
                mouseButton: mouseButton
            )
            downEvent?.post(tap: CGEventTapLocation.cghidEventTap)
            
            // Small delay
            Thread.sleep(forTimeInterval: 0.01)
            
            // Mouse up
            let upEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseButton == .left ? .leftMouseUp : mouseButton == .right ? .rightMouseUp : .otherMouseUp,
                mouseCursorPosition: point,
                mouseButton: mouseButton
            )
            upEvent?.post(tap: CGEventTapLocation.cghidEventTap)
            
            if numClicks > 1 {
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }
    
    /// Execute a drag action from start to end point
    /// - Parameters:
    ///   - startPoint: Starting point
    ///   - endPoint: Ending point
    ///   - duration: Duration in seconds
    ///   - buttonType: Mouse button type
    static func drag(from startPoint: CGPoint, to endPoint: CGPoint, duration: Double = 1.0, buttonType: String = "left") {
        let mouseButton: CGMouseButton
        switch buttonType.lowercased() {
        case "right":
            mouseButton = .right
        case "middle":
            mouseButton = .center
        default:
            mouseButton = .left
        }
        
        // Move to start position
        let moveEvent = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: startPoint, mouseButton: .left)
        moveEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.1)
        
        // Mouse down
        let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton == .left ? .leftMouseDown : mouseButton == .right ? .rightMouseDown : .otherMouseDown,
            mouseCursorPosition: startPoint,
            mouseButton: mouseButton
        )
        downEvent?.post(tap: .cghidEventTap)
        
        // Animate drag (simplified - move in steps)
        let steps = 10
        let dx = (endPoint.x - startPoint.x) / Double(steps)
        let dy = (endPoint.y - startPoint.y) / Double(steps)
        let stepDuration = duration / Double(steps)
        
        var currentPoint = startPoint
        for _ in 0..<steps {
            currentPoint.x += dx
            currentPoint.y += dy
            let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: mouseButton == .left ? .leftMouseDragged : mouseButton == .right ? .rightMouseDragged : .otherMouseDragged,
                mouseCursorPosition: currentPoint,
                mouseButton: mouseButton
            )
            dragEvent?.post(tap: CGEventTapLocation.cghidEventTap)
            Thread.sleep(forTimeInterval: stepDuration)
        }
        
        // Mouse up
        let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: mouseButton == .left ? .leftMouseUp : mouseButton == .right ? .rightMouseUp : .otherMouseUp,
            mouseCursorPosition: endPoint,
            mouseButton: mouseButton
        )
        upEvent?.post(tap: .cghidEventTap)
    }
    
    /// Execute keyboard input
    /// - Parameter text: Text to type
    static func typeText(_ text: String) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        for char in text {
            if let keyCode = getKeyCode(for: char) {
                // Key down
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
                
                // Small delay
                Thread.sleep(forTimeInterval: 0.01)
                
                // Key up
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
                keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
                
                // Small delay between keys
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }
    
    /// Press Enter/Return key
    static func pressEnter() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 0x24 // kVK_Return
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    /// Press Backspace/Delete key
    static func pressBackspace() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode: CGKeyCode = 0x33 // kVK_Delete
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.01)
        
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    /// Set clipboard content
    /// - Parameter text: Text to set in clipboard
    static func setClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Execute a hotkey combination
    /// - Parameter keys: Array of key names (e.g., ["command", "c"])
    static func hotkey(keys: [String]) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Separate modifier keys from regular keys
        var modifierKeys: [String] = []
        var regularKeys: [String] = []
        
        for key in keys {
            if getModifierKeyCode(for: key) != nil {
                modifierKeys.append(key)
            } else {
                regularKeys.append(key)
            }
        }
        
        // Press all modifier keys down
        var modifierKeyCodes: [CGKeyCode] = []
        for key in modifierKeys {
            if let keyCode = getModifierKeyCode(for: key) {
                modifierKeyCodes.append(keyCode)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }
        
        // Small delay for modifiers to register
        Thread.sleep(forTimeInterval: 0.05)
        
        // Press all regular keys down
        var regularKeyCodes: [CGKeyCode] = []
        for key in regularKeys {
            if let keyCode = getKeyCode(for: key) {
                regularKeyCodes.append(keyCode)
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
                keyDown?.post(tap: CGEventTapLocation.cghidEventTap)
            }
        }
        
        // Small delay
        Thread.sleep(forTimeInterval: 0.05)
        
        // Release regular keys first
        for keyCode in regularKeyCodes.reversed() {
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
        
        // Then release modifier keys
        for keyCode in modifierKeyCodes.reversed() {
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
            keyUp?.post(tap: CGEventTapLocation.cghidEventTap)
        }
    }
    
    /// Execute scroll action
    /// - Parameters:
    ///   - point: Scroll location
    ///   - clicks: Number of scroll clicks (positive = up, negative = down)
    ///   - shift: Whether to use horizontal scrolling
    static func scroll(at point: CGPoint, clicks: Int, shift: Bool = false) {
        let source = CGEventSource(stateID: .hidSystemState)
        
        // Move mouse to location
        let moveEvent = CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)
        moveEvent?.post(tap: CGEventTapLocation.cghidEventTap)
        Thread.sleep(forTimeInterval: 0.5)
        
        // Scroll event
        let scrollEvent = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 1, wheel1: Int32(clicks * 3), wheel2: 0, wheel3: 0)
        if shift {
            scrollEvent?.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(clicks * 3))
        }
        scrollEvent?.post(tap: CGEventTapLocation.cghidEventTap)
    }
    
    // MARK: - Helper Functions
    
    /// Get key code for a character or special key name
    /// - Parameter key: Character or key name string (e.g., "space", "enter", "backspace")
    /// - Returns: CGKeyCode or nil if not found
    private static func getKeyCode(for key: String) -> CGKeyCode? {
        // Check if it's a special key name first
        switch key.lowercased() {
        case "space":
            return 0x31 // kVK_Space
        case "enter", "return":
            return 0x24 // kVK_Return
        case "tab":
            return 0x30 // kVK_Tab
        case "delete", "backspace":
            return 0x33 // kVK_Delete
        case "escape", "esc":
            return 0x35 // kVK_Escape
        case "up":
            return 0x7E // kVK_UpArrow
        case "down":
            return 0x7D // kVK_DownArrow
        case "left":
            return 0x7B // kVK_LeftArrow
        case "right":
            return 0x7C // kVK_RightArrow
        case "a": return 0x00
        case "b": return 0x0B
        case "c": return 0x08
        case "d": return 0x02
        case "e": return 0x0E
        case "f": return 0x03
        case "g": return 0x05
        case "h": return 0x04
        case "i": return 0x22
        case "j": return 0x26
        case "k": return 0x28
        case "l": return 0x25
        case "m": return 0x2E
        case "n": return 0x2D
        case "o": return 0x1F
        case "p": return 0x23
        case "q": return 0x0C
        case "r": return 0x0F
        case "s": return 0x01
        case "t": return 0x11
        case "u": return 0x20
        case "v": return 0x09
        case "w": return 0x0D
        case "x": return 0x07
        case "y": return 0x10
        case "z": return 0x06
        default:
            // For single character keys, lowercase first for case-insensitive matching
            let lowerKey = key.lowercased()
            if lowerKey.count == 1, let char = lowerKey.first {
                // Recurse with the lowercase single character
                // This will match the letter cases above
                return getKeyCode(for: char)
            }
            return nil
        }
    }
    
    /// Get key code for a character
    /// - Parameter character: Single character
    /// - Returns: CGKeyCode or nil if not found
    private static func getKeyCode(for character: Character) -> CGKeyCode? {
        // Convert to string and lowercase for case-insensitive matching
        let keyString = String(character).lowercased()
        return getKeyCode(for: keyString)
    }
    
    private static func getModifierKeyCode(for key: String) -> CGKeyCode? {
        switch key.lowercased() {
        case "command", "cmd":
            return 0x37 // kVK_Command
        case "control", "ctrl":
            return 0x3B // kVK_Control
        case "option", "alt":
            return 0x3A // kVK_Option
        case "shift":
            return 0x38 // kVK_Shift
        default:
            return nil
        }
    }
}

extension CGPoint {
    /// Create CGPoint from Double values
    init(x: Double, y: Double) {
        self.init(x: CGFloat(x), y: CGFloat(y))
    }
    
    /// Get x as Double
    var xDouble: Double {
        return Double(self.x)
    }
    
    /// Get y as Double
    var yDouble: Double {
        return Double(self.y)
    }
}
