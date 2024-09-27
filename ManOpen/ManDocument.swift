//
//  ManDocument.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/9/14.
//
//

import Cocoa
import ApplicationServices
import FoundationAdditions

private let RestoreWindowDictKey = "RestoreWindowInfo"
private let RestoreSectionKey    = "Section"
private let RestoreTitleKey      = "Title"
private let RestoreNameKey       = "Name"
private let RestoreFileURLKey    = "URL"
private let RestoreFileTypeKey   = "DocType"

private let ManWindowSizeKey = "ManWindowSize"

private var filterCommand: String {
	let defaults = UserDefaults.standard
	
	/* HTML parser in tiger got slow... RTF is faster, and is usable now that it supports hyperlinks */
	//let tool = "cat2html"
	let tool = "cat2rtf"
	var command = Bundle.main.path(forAuxiliaryExecutable: tool)!
	
	command = escapePath(command, addSurroundingQuotes: true)
	command += " -lH" // generate links, mark headers
	if defaults.bool(forKey: kUseItalics) {
		command += " -i"
	}
	if !defaults.bool(forKey: kUseBold) {
		command += " -g"
	}
	
	return command
}

final class ManDocument: NSDocument, NSWindowDelegate {
	@IBOutlet weak var textScroll: NSScrollView!
	@IBOutlet weak var titleStringField: NSTextField!
	@IBOutlet weak var openSelectionButton: NSButton!
	@IBOutlet weak var sectionPopup: NSPopUpButton!
	private var hasLoaded = false
	private var restoreData = [String: Any]()
	var sections: [(name: String, range: NSRange)] = [(name: String, range: NSRange)]()
	
	var shortTitle = ""
	var copyURL: URL?
	var taskData: Data?
	
	private var textView: ManTextView {
		return textScroll.contentView.documentView as! ManTextView
	}
	
	override var windowNibName: NSNib.Name? {
		return "ManPage"
	}
	
	override class func canConcurrentlyReadDocuments(ofType typeName: String) -> Bool {
		return true
	}
	
	override func windowControllerDidLoadNib(_ aController: NSWindowController) {
		let defaults = UserDefaults.standard
		let sizeString: String? = defaults[ManWindowSizeKey]
		
		super.windowControllerDidLoadNib(aController)
		
		if let sizeString {
			let windowSize = NSSize(string: sizeString)
			let window = textView.window!
			var frame = window.frame
			
			if windowSize.width > 30.0 && windowSize.height > 30 {
				frame.size = windowSize
				window.setFrame(frame, display: false)
			}
		}
		
		titleStringField.stringValue = shortTitle
		textView.textStorage?.mutableString.setString(NSLocalizedString("Loading...", comment: "Before the man page is loaded"))
		textView.backgroundColor = defaults.manBackgroundColor
		textView.textColor = defaults.manTextColor
		
		DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.milliseconds(10)) {
			self.showData()
		}
		
		textView.window?.makeFirstResponder(textView)
		textView.window?.delegate = self
	}
	
	override func read(from url: URL, ofType typeName: String) throws {
		switch typeName {
		case "man":
			loadManFile(url.path, isGzip: false)
			
		case "mangz":
			loadManFile(url.path, isGzip: true)
			
		case "cat":
			loadCatFile(url.path, isGzip: false)
			
		case "catgz":
			loadCatFile(url.path, isGzip: true)
			
		default:
			throw CocoaError(.fileReadCorruptFile, userInfo:
				[NSLocalizedDescriptionKey: NSLocalizedString("Invalid document type", comment:"Invalid document type"),
				 NSURLErrorKey: url])
		}
		
		// strip extension twice in case it is a e.g. "1.gz" filename
		self.shortTitle = url.deletingPathExtension().deletingPathExtension().lastPathComponent
		copyURL = url
		
		restoreData = [RestoreFileURLKey: url,
		               RestoreFileTypeKey: typeName]
		
		if taskData == nil {
			throw CocoaError(.fileReadUnknown, userInfo:
				[NSLocalizedDescriptionKey: NSLocalizedString("Could not read manual data", comment: "Could not read manual data"),
				 NSURLErrorKey: url])
		}
	}
	
	
	/// Standard NSDocument method.  We only want to override if we aren't
	/// representing an actual file.
	override var displayName: String! {
		get {
			return fileURL != nil ? super.displayName : shortTitle
		}
		set {
			super.displayName = newValue
		}
	}
	
	override init() {
		super.init()
	}
	
	convenience init?(name: String, section: String? = nil, manPath: String? = nil, title: String) {
		self.init()
		loadDocument(name: name, section: section, manPath: manPath, title: title)
	}
	
	private func loadDocument(name: String, section: String? = nil, manPath: String? = nil, title: String) {
		let docController = ManDocumentController.shared as! ManDocumentController
		var command = docController.manCommand(manPath: manPath)
		fileType = "man"
		shortTitle = title
		
		if let section, !section.isEmpty {
			command += " " + section.lowercased()
			copyURL = URL(string: URL_SCHEME_PREFIX + "//\(section)/\(name)")
		} else {
			copyURL = URL(string: URL_SCHEME_PREFIX + "//\(title)")
		}
		
		restoreData = [RestoreNameKey: name,
			RestoreTitleKey: title,
			RestoreSectionKey: section ?? ""]
		
		command += " " + name
		
		loadCommand(command)
	}
	
	func loadCommand(_ command: String) {
		let docController = ManDocumentController.shared as! ManDocumentController
		let fullCommand = "\(command) | \(filterCommand)"
		taskData = try? docController.dataByExecutingCommand(fullCommand)
		
		showData()
	}
	
	func showData() {
		let defaults = UserDefaults.standard
		guard textScroll != nil /* nib is not yet loaded */ && !hasLoaded else {
			return
		}
		
		let manFont = defaults.manFont
		let linkColor = defaults.manLinkColor
		let textColor = defaults.manTextColor
		let backgroundColor = defaults.manBackgroundColor
		let storage: NSTextStorage = {
			var storage1: NSTextStorage? = nil
			if let taskData {
				if taskData.isRTFData {
					storage1 = NSTextStorage(rtf: taskData, documentAttributes: nil)
				} else {
					storage1 = NSTextStorage(html: taskData, options: [:], documentAttributes: nil)
				}
			}
			
			return storage1 ?? NSTextStorage()
		}()
		
		if storage.string.rangeOfCharacter(from: CharacterSet.letters) == nil {
			storage.mutableString.setString(NSLocalizedString("\nNo manual entry.", comment: "'No manual entry', preceeded by a newline"))
		}
		
		sections.removeAll()
		
		let manager = NSFontManager.shared
		let family = manFont.familyName ?? manFont.fontName
		let size = manFont.pointSize
		
		// MARK: Iterate over data
		exceptionBlock(try: { () -> Void in
			var currIndex = 0
			storage.beginEditing()
			
			while currIndex < storage.length {
				var currRange = NSRange(location: 0, length: 0)
				let attribs = storage.attributes(at: currIndex, effectiveRange: &currRange)
				let font = attribs[.font] as? NSFont
				
				if let font, font.familyName != "Courier" {
					//Using mutableString so we don't have to do Swift String range conversions.
					self.add(sectionHeader: storage.mutableString.substring(with: currRange), range: currRange)
				}
				
				let isLink = attribs[.link] != nil
				//Convert link to something that Terminal likes.
				//TODO: put this in cat2rtf!
				if let link = attribs[.link] as? URL,
				   let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
				   components.scheme == URL_SCHEME {
					let path = components.host ?? components.path
					var comp2 = URLComponents()
					comp2.scheme = URL_SCHEME
					if let fp = path.range(of: "("),
					   let lp = path.range(of: ")") {
						comp2.host = String(path[fp.upperBound ..< lp.lowerBound])
						comp2.path = "/" + String(path[path.startIndex ..< fp.lowerBound])
					} else {
						var path2 = path
						if path2.hasPrefix("/") {
							path2.removeFirst()
						}
						comp2.host = path2
					}
					if let newURL = comp2.url {
						storage.addAttribute(.link, value: newURL, range: currRange)
					}
				}
				
				if var font {
					if font.familyName != family {
						font = manager.convert(font, toFamily: family)
					}
					if font.pointSize != size {
						font = manager.convert(font, toSize: size)
					}
					
					storage.addAttribute(.font, value: font, range: currRange)
				}
				
				/*
				* Starting in 10.3, there is a -setLinkTextAttributes: method to set these, without having to
				* determine the ranges ourselves.  However, since we are already iterating all the ranges
				* for other reasons, may as well keep the old way.
				*/
				if isLink {
					storage.addAttribute(.foregroundColor, value: linkColor, range: currRange)
				} else {
					storage.addAttribute(.foregroundColor, value: textColor, range: currRange)
				}
				
				currIndex = currRange.upperBound
			}
		}, catch: { (localException) -> Void in
			Swift.print("Exception during formatting: \(localException)")
		}, finally: {
			storage.endEditing()
		})
		
		textView.layoutManager?.replaceTextStorage(storage)
		textView.window?.invalidateCursorRects(for: textView)
		textView.backgroundColor = backgroundColor
		setupSectionPopup()
		
		/*
		* The 10.7 document reloading stuff can cause the loading methods to be invoked more than
		* once, and the second time through we have thrown away our raw data.  Probably indicates
		* some overkill code elsewhere on my part, but putting in the hadLoaded guard to only
		* avoid doing anything after we have loaded real data seems to help.
		*/
		if taskData != nil {
			hasLoaded = true
		}
		
		// no need to keep around rtf data
		taskData = nil
	}
	
	func setupSectionPopup() {
		sectionPopup.removeAllItems()
		sectionPopup.addItem(withTitle: "Section:")
		sectionPopup.isEnabled = !sections.isEmpty
		
		if sectionPopup.isEnabled {
			sectionPopup.addItems(withTitles: sections.map({$0.name}))
		}
	}
	
	func add(sectionHeader header1: String, range: NSRange) {
		let header = header1.trimmingCharacters(in: CharacterSet.newlines)
		/* Make sure it is a header -- error text sometimes is not Courier, so it gets passed in here. */
		guard header.rangeOfCharacter(from: CharacterSet.uppercaseLetters) != nil,
			header.rangeOfCharacter(from: CharacterSet.lowercaseLetters) == nil else {
				return
		}
		var label = header
		var count = 1
		
		/* Check for dups (e.g. lesskey(1) ) */
		while sections.map({$0.name}).contains(label) {
			count += 1
			label = "\(header) [\(count)]"
		}
		sections.append((label, range))
	}
	
	func loadManFile(_ filename: String, isGzip: Bool = false) {
		let defaults = UserDefaults.standard
		var nroffFormat: String = defaults[kNroffCommand]!
		let hasQuote = nroffFormat.range(of: "'%@'") != nil
		
		/* If Gzip, change the command into a filter of the output of gzcat.  I'm
		getting the feeling that the customizable nroff command is more trouble
		than it's worth, especially now that OSX uses the good version of gnroff */
		if isGzip {
			let repl = hasQuote ? "'%@'" : "%@"
			if let replRange = nroffFormat.range(of: repl) {
				var formatCopy = nroffFormat
				formatCopy.replaceSubrange(replRange, with: "")
				nroffFormat = "/usr/bin/gzip -dc \(repl) | \(formatCopy)"
			}
		}
		
		let nroffCommand = String(format: nroffFormat, escapePath(filename, addSurroundingQuotes: !hasQuote))
		loadCommand(nroffCommand)
	}
	
	func loadCatFile(_ filename: String, isGzip: Bool = false) {
		let binary = isGzip ? "/usr/bin/gzip -dc" : "/bin/cat"
		loadCommand("\(binary) '\(escapePath(filename, addSurroundingQuotes: false))'")
	}
	
	@IBAction func saveCurrentWindowSize(_ sender: AnyObject?) {
		let size = textView.window!.frame.size
		UserDefaults.standard[ManWindowSizeKey] = size.stringValue
	}
	
	@IBAction func openSelection(_ sender: AnyObject?) {
		let selectedRange = textView.selectedRange()
		let str = textView.string
		
		if selectedRange.length > 0, let rang = Range(selectedRange, in: str) {
			let selectedString = String(str[rang])
			(ManDocumentController.shared as! ManDocumentController).openString(selectedString)
		}
		
		textView.window?.makeFirstResponder(textView)
	}
	
	@IBAction func displaySection(_ sender: AnyObject?) {
		let section = sectionPopup.indexOfSelectedItem
		if section > 0 && section <= sections.count {
			let range = sections[section - 1].range
			textView.scrollToTop(of: range)
		}
	}
	
	@IBAction func copyURL(_ sender: AnyObject?) {
		if let copyURL {
			let pb = NSPasteboard.general
			var types = [NSPasteboard.PasteboardType]()
			
			types.append(.URL)
			if copyURL.isFileURL {
				types.append(.fileURL)
			}
			types.append(.string)
			pb.declareTypes(types, owner: nil)
			
			(copyURL as NSURL).write(to: pb)
			pb.setString("<\(copyURL.absoluteString)>", forType: .string)
			if copyURL.isFileURL {
				pb.setPropertyList([copyURL], forType: .fileURL)
			}
		}
	}
	
	override func runPageLayout(_ sender: Any?) {
		NSApplication.shared.runPageLayout(sender)
	}
	
	override func printOperation(withSettings printSettings: [NSPrintInfo.AttributeKey : Any]) throws -> NSPrintOperation {
		let operation = NSPrintOperation(view: textView, printInfo: NSPrintInfo(dictionary: printSettings))
		let printInfo = operation.printInfo
		printInfo.isVerticallyCentered = false
		printInfo.isHorizontallyCentered = true
		printInfo.horizontalPagination = .fit
		
		return operation
	}
	
	override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		if menuItem.action == #selector(ManDocument.copyURL(_:)) {
			return copyURL != nil
		}
		
		return super.validateMenuItem(menuItem)
	}
	
	// MARK: NSWindowRestoration functions
	override func encodeRestorableState(with coder: NSCoder) {
		super.encodeRestorableState(with: coder)
		coder.encode(restoreData, forKey: RestoreWindowDictKey)
	}
	
	override func restoreState(with coder: NSCoder) {
		super.restoreState(with: coder)
		
		if !coder.containsValue(forKey: RestoreWindowDictKey) {
			return
		}
		
		if let restoreInfo = coder.decodeObject(forKey: RestoreWindowDictKey) as? [String: Any] {
			if let aRestoreName = restoreInfo[RestoreNameKey] as? String,
				let title = restoreInfo[RestoreTitleKey] as? String {
				let section = restoreInfo[RestoreSectionKey] as? String
				let manPath = UserDefaults.standard.manPath
				
				loadDocument(name: aRestoreName, section: section, manPath: manPath, title: title)
				/* Usually, URL-backed documents have been automatically restored already
				(the copyURL would be set), but just in case... */
			} else if let url = restoreInfo[RestoreFileURLKey] as? URL, copyURL == nil,
				let type = restoreInfo[RestoreFileTypeKey] as? String {
				
				do {
					try read(from: url, ofType: type)
				} catch _ {
				}
			}
			
			titleStringField.stringValue = shortTitle
			
			for vc in windowControllers {
				vc.synchronizeWindowTitleWithDocumentName()
			}
		}
	}
}
