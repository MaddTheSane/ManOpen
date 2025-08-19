//
//  NSUserDefaults+additions.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/8/14.
//
//

import Cocoa
import FoundationAdditions

let manTextColorKey = "ManTextColor"
let manLinkColorKey = "ManLinkColor"
let manFontKey		= "ManFont"
let manPathKey		= "ManPath"
let manBackgroundColorKey = "ManBackgroundColor"

private func color(for key: String, defaults: UserDefaults = UserDefaults.standard) -> NSColor? {
	if let colorData: Data = defaults[key] {
		var colorRet: NSColor? = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
		if colorRet == nil {
			if let colorRet1 = NSUnarchiver.unarchiveObject(with: colorData) as? NSColor {
				colorRet = colorRet1
				defaults[key] = dataForColor(colorRet1)
			}
		}
		return colorRet
	}
	
	return nil
}

internal func dataForColor(_ color: NSColor) -> Data {
	return try! NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: true)
}

extension UserDefaults {
	var manTextColor: NSColor {
		get {
			if let newCol = color(for: manTextColorKey, defaults: self) {
				return newCol
			} else {
				removeObject(forKey: manTextColorKey)
			}
			return color(for: manTextColorKey, defaults: self)!
		}
		set {
			self[manTextColorKey] = dataForColor(newValue)
		}
	}
	
	var manLinkColor: NSColor {
		get {
			if let newCol = color(for: manLinkColorKey, defaults: self) {
				return newCol
			} else {
				removeObject(forKey: manLinkColorKey)
			}
			return color(for: manLinkColorKey, defaults: self)!
		}
		set {
			self[manLinkColorKey] = dataForColor(newValue)
		}
	}
	
	var manBackgroundColor: NSColor {
		get {
			if let newCol = color(for: manBackgroundColorKey, defaults: self) {
				return newCol
			} else {
				removeObject(forKey: manBackgroundColorKey)
			}
			return color(for: manBackgroundColorKey, defaults: self)!
		}
		set {
			self[manBackgroundColorKey] = dataForColor(newValue)
		}
	}
	
	var manPath: String {
		get {
			return self[manPathKey]!
		}
		set {
			self[manPathKey] = newValue
		}
	}
	
	var manFont: NSFont {
		if let fontString: String = self[manFontKey],
		   let spaceRange = fontString.range(of: " ") {
			let sizeStr = fontString[fontString.startIndex..<spaceRange.lowerBound]
			if let size1 = CGFloat.NativeType(sizeStr) {
				let size = CGFloat(floatLiteral: size1)
				let name = String(fontString[spaceRange.upperBound..<fontString.endIndex])
				if let font = NSFont(name: name, size: size) {
					return font
				}
			}
		}
		
		if #available(macOS 10.15, *) {
			return NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
		} else {
			return NSFont.userFixedPitchFont(ofSize: 12.0)! // Monaco, or Menlo
		}
	}
}
