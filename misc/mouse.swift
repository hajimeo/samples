#!/usr/bin/env swift
import Foundation
import CoreGraphics // I had to import this in order for it to work

let source = CGEventSource.init(stateID: .hidSystemState)
let position = CGPoint(x: 75, y: 100)
let e = CGEvent(mouseEventSource: source, mouseType: .otherMouseUp, mouseCursorPosition: position , mouseButton: CGMouseButton(rawValue: 3)!) // 3 for button4, 4 for button5
e?.post(tap: .cghidEventTap)
