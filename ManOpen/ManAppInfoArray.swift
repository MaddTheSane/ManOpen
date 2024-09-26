//
//  ManAppInfoArray.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/10/14.
//
//

import Cocoa
import CoreServices

private func generateManInfos() -> [ManAppInfo] {
	var anAppInfo = [ManAppInfo]()
	var components = URLComponents()
	components.scheme = URL_SCHEME
	components.host = "man"
	let allBundleURLs: [URL]?
	if #available(macOS 12.0, *) {
		allBundleURLs = NSWorkspace.shared.urlsForApplications(toOpen: components.url!)
	} else {
		allBundleURLs = LSCopyApplicationURLsForURL(components.url! as NSURL, .viewer)?.takeRetainedValue() as? [URL]
	}
	guard let allBundleURLs else {
		return []
	}
	anAppInfo.reserveCapacity(allBundleURLs.count)
	
	for bundleURL in allBundleURLs {
		if let mai = ManAppInfo(url: bundleURL) {
			anAppInfo.append(mai)
		}
	}
	
	return anAppInfo
}

final class ManAppInfoArray: Sequence {
	private(set) var allManViewerApps = generateManInfos()
	
	init() {
		sortApps()
	}
	
	var count: Int {
		return allManViewerApps.count
	}
	
	func makeIterator() -> IndexingIterator<[ManAppInfo]> {
		return allManViewerApps.makeIterator()
	}
	
	subscript(location: Int) -> ManAppInfo {
		return allManViewerApps[location]
	}
	
	func addApp(identifier id: String, shouldResort sort: Bool = false) {
		guard let info = ManAppInfo(bundleID: id) else {
			//NSBeep()
			//return
			fatalError("Could not find application with bundle identifier \"\(id)\"")
		}
		if !allManViewerApps.contains(info) {
			allManViewerApps.append(info)
			if sort {
				sortApps()
			}
		}
	}
	
	private func sortApps() {
		allManViewerApps.sort { (lhs, rhs) -> Bool in
			let toRet = lhs.localizedCaseInsensitiveCompare(rhs)
			return toRet == .orderedAscending
		}
	}
	
	func firstIndex(withBundleID bundleID: String?) -> Int? {
		guard let bundleID else {
			return nil
		}
		
		for (i, obj) in allManViewerApps.enumerated() {
			if obj == bundleID {
				return i
			}
		}
		
		return nil
	}
	
	func indexes(withBundleID bundleID: String) -> IndexSet {
		var idxSet = IndexSet()
		
		for (i, obj) in allManViewerApps.enumerated() {
			if obj == bundleID {
				idxSet.insert(i)
			}
		}
		
		return idxSet
	}
}
