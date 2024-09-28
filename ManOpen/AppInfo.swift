//
//  AppInfo.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/10/14.
//
//

import Cocoa

func ==(lhs: ManAppInfo, rhs: String) -> Bool {
	let toRet = lhs.bundleID.caseInsensitiveCompare(rhs)
	return toRet == ComparisonResult.orderedSame
}

final class ManAppInfo: Hashable, CustomDebugStringConvertible, CustomStringConvertible {
	let bundleID: String
	let appURL: URL
	
	private(set) lazy var displayName: String = {
		let url = self.appURL
		var infoDict: [String: Any]? = CFBundleCopyInfoDictionaryForURL(url as NSURL) as? [String : Any]
		
		if infoDict == nil {
			infoDict = Bundle(url: url)!.infoDictionary
		}
		
		var niceName: String = {
			do {
				let resVals = try url.resourceValues(forKeys: [.localizedNameKey])
				if let aNiceStr = resVals.localizedName {
					return aNiceStr
				}
			} catch _ {}
			
			return url.lastPathComponent
			}()
		
		if let infoDict, let appVersion = infoDict["CFBundleShortVersionString"] as? String {
			niceName = "\(niceName) (\(appVersion))"
		}
		
		return niceName
		}()
	
	func isEqual(_ other: Any?) -> Bool {
		if let isAppInfo = other as? ManAppInfo {
			return self == isAppInfo
		} else if let isString = other as? String {
			return self == isString
		} else {
			return false
		}
	}
	
	convenience init?(bundleID aBundleID: String) {
		guard let bundURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: aBundleID) else {
			return nil
		}
		self.init(url: bundURL)
	}

	init?(url: URL) {
		appURL = url
		
		guard let ident = Bundle(url: url)?.bundleIdentifier else {
			return nil
		}
		bundleID = ident
	}
	
	func hash(into hasher: inout Hasher) {
		guard let ident = try? appURL.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
			  // sssh... fileResourceIdentifiers are secretly NSData objects
			  let ident2 = ident as? NSData else {
			hasher.combine(bundleID.lowercased())
			return
		}
		hasher.combine(ident2 as Data)
	}
	
	func compare(_ string: ManAppInfo) -> ComparisonResult {
		return displayName.compare(string.displayName, options: [.caseInsensitive, .numeric])
	}
	
	func localizedStandardCompare(_ string: ManAppInfo) -> ComparisonResult {
		return displayName.localizedStandardCompare(string.displayName)
	}
	
	func localizedCaseInsensitiveCompare(_ string: ManAppInfo) -> ComparisonResult {
		return displayName.localizedCaseInsensitiveCompare(string.displayName)
	}
	
	var debugDescription: String {
		return "\(bundleID), \(displayName)"
	}
	
	var description: String {
		return displayName
	}
	
	static func ==(lhs: ManAppInfo, rhs: ManAppInfo) -> Bool {
		let toRet = lhs.bundleID.caseInsensitiveCompare(rhs.bundleID)
		return toRet == .orderedSame
	}
}
