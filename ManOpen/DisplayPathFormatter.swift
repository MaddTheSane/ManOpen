//
//  DisplayPathFormatter.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/8/14.
//
//

import Foundation

private let resHome = (NSHomeDirectory() as NSString).resolvingSymlinksInPath + "/"

/// Formatter to abbreviate folders in the user's home directory for a nicer display.
final class DisplayPathFormatter: Formatter {
	override func string(for obj: Any?) -> String? {
		if let aStr = obj as? NSString {
			var anew = aStr.abbreviatingWithTildeInPath
			
			/* The above method may not work if the home directory is a symlink, and our path is already resolved */
			if (anew as NSString).isAbsolutePath {
				
				if anew.hasPrefix(resHome) {
					anew.replaceSubrange(anew.range(of: resHome)!, with: "~/")
				}
			}
			
			return anew
		}
		return nil
	}
	
	override func getObjectValue(_ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?, for string: String, errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?) -> Bool {
		obj?.pointee = (string as NSString).expandingTildeInPath as NSString
		
		return true
	}
}
