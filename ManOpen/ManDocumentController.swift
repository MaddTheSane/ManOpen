//
//  ManDocumentController.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/8/14.
//
//

import Cocoa
import FoundationAdditions
import zlib

private let MAN_BINARY = "/usr/bin/man"
//#define MANPATH_FORMAT @" -m '%@'"  // There's a bug in man(1) on OSX and OSXS
private let MANPATH_FORMAT = " -M '%@'"

/// We need to make sure we handle all sorts of characters in filenames. The way
/// to do that is surround the path with ' characters -- but then we have to
/// escape any `'` characters actually in the string. To do that, you need to add a
/// `'` to close the quote section, add an escaped `'`, then add another `'` to start
/// quoting again. Something like '\'' or '"'"'. E.g.: */foo/bar* -> *'/foo/bar'*,
/// */foo bar/baz* -> *'/foo bar/baz'*, */Apple's Stuff* -> *'/Apple'\\''s Stuff'*.
func escapePath(_ path: String, addSurroundingQuotes: Bool = false) -> String {
	var modPath = path
	if path.range(of: "'") != nil {
		var newString = ""
		let scanner = Scanner(string: path)
		
		scanner.charactersToBeSkipped = nil
		
		while !scanner.isAtEnd {
			var betweenString: NSString? = nil
			if scanner.scanUpTo("'", into: &betweenString) {
				if let betweenString {
					newString += betweenString as String
				}
				if scanner.scanString("'", into: nil) {
					newString += "'\\''"
				}
			}
		}
		
		modPath = newString
	}
	
	if addSurroundingQuotes {
		modPath = "'\(modPath)'"
	}
	
	return modPath;
}

@main
class ManDocumentController: NSDocumentController, NSApplicationDelegate {
	@IBOutlet weak var helpScrollView: NSScrollView!
	@IBOutlet weak var openTextPanel: NSPanel!
	@IBOutlet weak var aproposPanel: NSPanel!
	@IBOutlet weak var helpPanel: NSPanel!
	@IBOutlet weak var aproposField: NSTextField!
	@IBOutlet weak var openTextField: NSTextField!
	@IBOutlet weak var openSectionPopup: NSPopUpButton!
	var startedUp = false
	private var nibObjects = [AnyObject]()
	private var messagePort: CFMessagePort?
	
	@objc func ensureActive() {
		if !NSApplication.shared.isActive {
			NSApplication.shared.activate(ignoringOtherApps: true)
		}
	}
	
	@objc func openApropos(_ apropos: String, manPath: String? = nil, forceToFront force: Bool = true) {
		if force {
			ensureActive()
		}
		
		openAproposDocument(apropos, manPath: manPath ?? UserDefaults.standard.manPath)
	}
	
	var useModalPanels: Bool {
		return !(UserDefaults.standard[kKeepPanelsOpen]!)
	}
	
	// MARK: - NSApplicationDelegate
	
	func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
		return true
	}
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.servicesProvider = self
		/* Remember window positions, in case they're non-modal */
		openTextPanel.setFrameUsingName("OpenTitlePanel")
		openTextPanel.setFrameAutosaveName("OpenTitlePanel")
		aproposPanel.setFrameUsingName("AproposPanel")
		aproposPanel.setFrameAutosaveName("AproposPanel")
		
		startedUp = true
	}
	
	/// By default, NSApplication will want to open an untitled document at
	/// startup and when no windows are open. Check our preferences.
	func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
		if startedUp {
			return UserDefaults.standard["OpenPanelWhenNoWindows"] ?? false
		} else {
			return UserDefaults.standard["OpenPanelOnStartup"] ?? false
		}
	}
	
	func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
		if applicationShouldOpenUntitledFile(sender) {
			if !openTextPanel.isVisible {
				openSectionPopup.selectItem(at: 0)
			}
			openTextField.selectText(self)
			DispatchQueue.global().async(execute: { () -> Void in
				usleep(0)
				DispatchQueue.main.sync(execute: { () -> Void in
					self.openTextPanel.makeKeyAndOrderFront(self)
				})
			})
			return true
		}
		return false
	}
	
	// MARK: -
	
	override func removeDocument(_ document: NSDocument) {
		let autoQuit: Bool = UserDefaults.standard[kQuitWhenLastClosed]!
		
		super.removeDocument(document)
		
		if documents.count == 0 && autoQuit {
			DispatchQueue.global().async(execute: { () -> Void in
				usleep(0)
				DispatchQueue.main.sync(execute: { () -> Void in
					NSApplication.shared.terminate(self)
				})
			})
			
		}
	}
	
	func manCommand(manPath: String? = nil) -> String {
		var command = MAN_BINARY
		
		if let manPath, !manPath.isEmpty {
			command += " -M '\(escapePath(manPath))'"
		}
		
		return command
	}
	
	func dataByExecutingCommand(_ command: String, maxLength: Int = 0, extraEnv: Dictionary<String, String>? = nil) throws -> Data {
		let pipe = Pipe()
		let task = Process()
		var output: Data
		
		if let extraEnv {
			var environment = ProcessInfo.processInfo.environment
			environment += extraEnv
			task.environment = environment
		}
		
		task.launchPath = "/bin/sh"
		task.arguments = ["-c", command]
		task.standardOutput = pipe
		task.standardError = FileHandle.nullDevice
		task.qualityOfService = .userInitiated
		task.launch()
		
		if maxLength > 0 {
			if #available(macOS 10.15.4, *) {
				output = try pipe.fileHandleForReading.read(upToCount: maxLength) ?? Data()
			} else {
				output = pipe.fileHandleForReading.readData(ofLength: maxLength)
			}
			task.terminate()
		} else {
			output = try pipe.fileHandleForReading.readDataToEndOfFileIgnoreInterrupt()
		}
		task.waitUntilExit()
		
		return output
	}
	
	func dataByExecutingCommand(_ command: String, manPath: String) throws -> Data {
		return try dataByExecutingCommand(command, extraEnv: ["MANPATH" : manPath])
	}
	
	func manFile(name: String, section: String? = nil, manPath: String? = nil) -> String? {
		var command = manCommand(manPath: manPath)
		command += " -w \(section ?? "") \(name)"
		if let data = try? dataByExecutingCommand(command) {
			if data.isEmpty {
				return nil
			}
			
			let manager = FileManager.default
			var len = data.count
			
			//TODO: use Swift equivalent.
			data.withUnsafeBytes { urbp in
				// 0A is == '\n'
				if let newlinePtr = memchr(urbp.baseAddress, 0x0A, len) {
					len = urbp.baseAddress!.distance(to: newlinePtr)
				}
			}
			
			let filename = data.withUnsafeBytes { ptr in
				ptr.baseAddress!.withMemoryRebound(to: Int8.self, capacity: len) { ptr2 in
					manager.string(withFileSystemRepresentation: ptr2, length: len)
				}
			}
			if manager.fileExists(atPath: filename) {
				return filename
			}
		}
		return nil
	}
	
	func type(from url: URL) -> String? {
		let manager = FileManager.default
		var catType = "cat"
		var manType = "man"
		var len: UInt64
		if let theAttribs = try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.fileSizeKey]),
			let aSize = theAttribs.fileSize {
			len = UInt64(aSize)
		} else if let anAttrib = try? manager.attributesOfItem(atPath: url.resolvingSymlinksInPath().path) {
			if let tmplen = anAttrib[FileAttributeKey.size] as? NSNumber {
				len = tmplen.uint64Value
			} else {
				len = 0
			}
		} else {
			len = 0
		}
		let maxLength = Int(min(150, len))
		
		if maxLength == 0 {
			return catType
		}
		
		if let handle = try? FileHandle(forReadingFrom: url) {
			var fileHeader = handle.readData(ofLength: maxLength)
			
			if len > 1000000 {
				return nil
			}
			
			if fileHeader.isGzipData {
				if let gzf = url.withUnsafeFileSystemRepresentation({ (path) -> gzFile? in
					return gzopen(path, "rb")
				}) {
					fileHeader = Data(count: maxLength)
					let newSz = fileHeader.withUnsafeMutableBytes { (_ dat2: UnsafeMutableRawBufferPointer) -> Int32 in
						return gzread(gzf, dat2.baseAddress, UInt32(dat2.count))
					}
					fileHeader.count = Int(newSz)
					gzclose(gzf)
				} else {
					let command = "/usr/bin/gzip -dc '\(escapePath(url.path))'"
					fileHeader = try! dataByExecutingCommand(command, maxLength: maxLength)
				}
				manType = "mangz"
				catType = "catgz"
			}
			
			if fileHeader.isBinaryData {
				return nil
			}
			
			return fileHeader.isNroffData ? manType : catType
		} else {
			return catType
		}
	}
	
	/// The super implementation will only call `-makeDocument...`, etc. if the
	/// file's extension is listed in in the NSTypes section in Info.plist.
	/// Since we don't want to declare the typical .1, .2, etc. extensions,
	/// plus the fact that often man pages outside of the typical `MANPATH`
	/// directories often have other-than-standard extensions, we override
	/// completely to avoid that chance, and instead determine the type of
	/// the file based on contents.
	override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: (@escaping (NSDocument?, Bool, Error?) -> Void)) {
		let standardizedURL = url.standardized
		var error: Error? = nil
		let numDocuments = documents.count
		
		var document = self.document(for: standardizedURL)
		if document == nil {
			if let type = type(from: standardizedURL) {
				do {
					document = try makeDocument(withContentsOf: standardizedURL, ofType: type)
					document!.makeWindowControllers()
					addDocument(document!)
				} catch let anErr {
					error = anErr
				}
			} else {
				error = CocoaError(.fileReadUnknown, userInfo: [NSURLErrorKey: standardizedURL])
			}
		}
		
		let docAdded = numDocuments < documents.count
		
		if displayDocument {
			document?.showWindows()
		}
		
		completionHandler(document, !docAdded, error)
	}
	
	override func reopenDocument(for urlOrNil: URL?, withContentsOf contentsURL: URL, display displayDocument: Bool, completionHandler: (@escaping (NSDocument?, Bool, Error?) -> Void)) {
		openDocument(withContentsOf: urlOrNil ?? contentsURL, display: displayDocument, completionHandler: completionHandler)
	}
	
	/// Ignore the types; man/cat files can have any range of extensions.
	override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
		return openPanel.runModal().rawValue
	}
	
	func document(forTitle title: String) -> NSDocument? {
		for document in documents {
			if let manDoc = document as? ManDocument {
				if manDoc.shortTitle == title {
					return manDoc
				}
				continue
			}
			
			if let aproposDoc = document as? AproposDocument {
				if aproposDoc.displayName == title {
					return aproposDoc
				}
			}
		}
		return nil
	}
	
	override func awakeFromNib() {
		super.awakeFromNib()
		var helpPath = Bundle.main.url(forResource: "Help", withExtension: "rtf")
		if helpPath == nil {
			helpPath = Bundle.main.url(forResource: "Help", withExtension: "rtfd")
		}
		
		guard let helpPath else {
			return
		}
		
		(helpScrollView.contentView.documentView as! NSTextView).readRTFD(fromFile: helpPath.path)
	}
	
	/// A parallel for `-openDocumentWithContentsOfFile:` for a specific man page
	@discardableResult @objc
	func openDocument(name: String, section: String? = nil, manPath: String) -> ManDocument? {
		var title = name
		if let section, section.isEmpty == false {
			title = "\(name)(\(section))"
		}
		
		var document = self.document(forTitle: title) as? ManDocument
		if document == nil {
			document = ManDocument(name: name, section: section, manPath: manPath, title: title)
			
			if let filename = manFile(name: name, section: section, manPath: manPath) {
				let fileURL = URL(fileURLWithPath: filename).resolvingSymlinksInPath()
				noteNewRecentDocumentURL(fileURL)
				document?.fileURL = fileURL
			}
			
			addDocument(document!)
			document?.makeWindowControllers()
		}
		
		document?.showWindows()
		
		return document
	}
	
	@discardableResult @objc
	func openAproposDocument(_ apropos: String, manPath: String) -> AproposDocument? {
		let title = "Apropos \(apropos)"
		var document = self.document(forTitle: title) as? AproposDocument
		
		if document == nil {
			document = AproposDocument(string: apropos, manPath: manPath, title: title)
			
			if let document {
				addDocument(document)
			}
			document?.makeWindowControllers()
		}
		
		document?.showWindows()
		
		return document
	}
	
	/// Parses word for stuff like "*file(3)*" to break out the section, then
	/// calls `openDocument(name:section:manPath:)` as appropriate.
	@discardableResult
	func openWord(_ word: String) -> ManDocument? {
		var base = word
		var section: String? = nil
		let lparenRange = word.range(of: "(")
		let rparenRange = word.range(of: ")")
		
		if let lp = lparenRange, let rp = rparenRange, lp.lowerBound < rp.lowerBound {			
			base = String(word[word.startIndex ..< lp.lowerBound])
			section = String(word[word.index(after: lp.lowerBound) ..< word.index(before: rp.upperBound)])
		}
		
		return openDocument(name: base, section: section, manPath: UserDefaults.standard.manPath)
	}
	
	func openString(_ string: String) {
		let words = getWordArray(string)
		if words.count > 20 {
			let locCount = NumberFormatter.localizedString(from: NSNumber(value: words.count), number: .decimal)
			let alert = NSAlert()
			alert.messageText = NSLocalizedString("Warning", comment: "Warning")
			alert.informativeText = String.localizedStringWithFormat(NSLocalizedString("This will open approximately %@ windows!", comment: "This will open approximately (the number of) windows!"), locCount)
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
			alert.addButton(withTitle: NSLocalizedString("Continue", comment: "Continue"))
			let aNum = alert.runModal()
			if aNum != .alertSecondButtonReturn {
				return
			}
		}
		
		openString(string, oneWordOnly: false)
	}
	
	/// Breaks string up into words and calls `openWord(_:)` on each one.
	/// Essentially opens a man page for each word in string, while doing
	/// some specialized processing as well -- treating "foo (5)" as one
	/// page, recombining words that nroff hyphenated across lines, and
	/// ignoring trailing commas.
	func openString(_ string: String, oneWordOnly oneOnly: Bool) {
		let scanner = Scanner(string: string)
		let whitespaceSet = CharacterSet.whitespacesAndNewlines
		let nonwhitespaceSet = whitespaceSet.inverted
		var aWord: NSString? = nil
		var lastWord: String! = nil
		
		scanner.charactersToBeSkipped = whitespaceSet
		
		while !scanner.isAtEnd {
			if scanner.scanCharacters(from: nonwhitespaceSet, into: &aWord) {
				if lastWord == nil {
					if let aWord {
						lastWord = aWord as String
					} else {
						continue
					}
					/* If there was a space between the name and section, join them */
				} else if aWord!.hasPrefix("(") && aWord!.hasSuffix(")") {
					openWord(lastWord + (aWord! as String))
					lastWord = nil
					if oneOnly {
						break
					}
					/* If (g)nroff hyphenated a word across lines, rejoin them */
				} else if lastWord.hasSuffix("-") {
					let lastIndex = lastWord.index(before: lastWord.endIndex)
					lastWord = String(lastWord[lastWord.startIndex..<lastIndex])
					if let aWord = aWord as String? {
						lastWord! += aWord
					}

				} else {
					/* SEE ALSO sections often have commas between items, ignore it */
					if lastWord.hasSuffix(",") {
						let lastIndex = lastWord.index(before: lastWord.endIndex)
						lastWord = String(lastWord[lastWord.startIndex..<lastIndex])
					}
					openWord(lastWord)
					lastWord = nil
					if oneOnly {
						break
					}
					if let aWord {
						lastWord = aWord as String
					}
				}
			}
		}
		
		if var lastWord {
			if lastWord.hasSuffix(",") {
				let lastIndex = lastWord.index(before: lastWord.endIndex)
				lastWord = String(lastWord[lastWord.startIndex..<lastIndex])
			}
			openWord(lastWord)
		}
	}
	
	@IBAction func orderFrontHelpPanel(_ sender: AnyObject!) {
		helpPanel.makeKeyAndOrderFront(sender)
	}
	
	@IBAction func orderFrontPreferencesPanel(_ sender: AnyObject?) {
		PrefPanelController.shared.showWindow(sender)
	}
	
	@IBAction func runPageLayout(_ sender: AnyObject!) {
		NSApp.runPageLayout(sender)
	}
	
	override init() {
		super.init()
		
		var context = CFMessagePortContext()
		
		// Set ourselves up for connections from the command line tool. Originally, this app used DO, but DO is deprecated, and even if it wasn't, it doesn't work in the sandbox. But Mach ports work, so we use that instead.
		// If anyone other than me is building this, then you will need to replace my developer group ID with your own below. And you'll probably need to make the same change in the app group in the entitlements as well.
		context.info = Unmanaged.passUnretained(self).toOpaque()
		messagePort = CFMessagePortCreateLocal(nil, "8D98N325TG.org.clindberg.ManOpen.MachIPC" as CFString, { port, messageID, data, context -> Unmanaged<CFData>? in
			guard let context, let data = data as Data? else {
				return nil
			}
			let ourself = Unmanaged<ManDocumentController>.fromOpaque(context).takeUnretainedValue()
			do {
				guard let commands = try NSKeyedUnarchiver.unarchivedObject(ofClasses: [NSDictionary.self, NSArray.self, NSString.self, NSNumber.self], from: data) as? [String: Any] else {
					return nil
				}
				
				let manPath = (commands["ManPath"] as? String) ?? UserDefaults.standard.manPath
				let apropos = (commands["Apropos"] as? Bool) ?? false
				let files = commands["Files"] as? [String]
				let namesAndSections = commands["NamesAndSections"] as? [[String: String]]
				
				if let files {
					for file in files {
						ourself.openDocument(withContentsOf: URL(fileURLWithPath: file), display: true) { document, wasOpen, error in
							// Do Nothing
						}
					}
				}
				
				if let namesAndSections {
					for nameAndSection in namesAndSections {
						guard let name = nameAndSection["Name"] else {
							continue
						}
						if apropos {
							ourself.openApropos(name, manPath: manPath, forceToFront: false)
						} else {
							ourself.openDocument(name: name, section: nameAndSection["Section"], manPath: manPath)
						}
					}
				}
				
			} catch {
				print("Encountered error decoding Message Port data: \(error)")
			}
			return nil
		}, &context, nil)
		
		// don't crash if creating a message port didn't work
		if let messagePort {
			let messagePortRLS = CFMessagePortCreateRunLoopSource(nil, messagePort, 0)
			CFRunLoopAddSource(CFRunLoopGetMain(), messagePortRLS, CFRunLoopMode.commonModes)
		}
		
		PrefPanelController.registerManDefaults()
		var tmpNibArray: NSArray? = nil
		Bundle.main.loadNibNamed("DocController", owner: self, topLevelObjects: &tmpNibArray)
		
		nibObjects = tmpNibArray as [AnyObject]? ?? []
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func openTitleFromPanel() {
		var aString = openTextField.stringValue
		let words = getWordArray(aString)
		
		/* If the string is of the form "3 printf", arrange it better for our parser.  Requested by Eskimo.  Also accept 'n' as a section */
		if words.count == 2 && aString.range(of: "(") == nil && isSectionWord(words[0]) {
			aString = "\(words[1])(\(words[0]))"
		}
		
		/* Append the section if chosen in the popup and not explicity defined in the string */
		if aString.count > 0 && openSectionPopup.indexOfSelectedItem > 0 && aString.range(of: "(") == nil {
			aString += "(\(openSectionPopup.indexOfSelectedItem))"
		}
		openString(aString)
		openTextField.selectText(self)
	}
	
	@IBAction func openSection(_ sender: AnyObject!) {
		let aTag = sender.tag ?? 0
		if aTag == 0 {
			openApropos("") // all pages
		} else if aTag == 20 {
			openApropos("(n)")
		} else {
			openApropos("(\(aTag))")
		}
	}
	
	@IBAction func openTextPanel(_ sender: AnyObject!) {
		if !openTextPanel.isVisible {
			openSectionPopup.selectItem(at: 0)
		}
		openTextField.selectText(self)
		
		if useModalPanels {
			if NSApp.runModal(for: openTextPanel) == .OK {
				openTitleFromPanel()
			}
		} else {
			openTextPanel.makeKeyAndOrderFront(self)
		}
	}
	
	func openAproposFromPanel() {
		openApropos(aproposField.stringValue)
		aproposField.selectText(self)
	}
	
	@IBAction func openAproposPanel(_ sender: NSView!) {
		aproposField.selectText(self)
		
		if useModalPanels {
			if NSApp.runModal(for: aproposPanel) == .OK {
				openAproposFromPanel()
			}
		} else {
			aproposPanel.makeKeyAndOrderFront(self)
		}
	}
	
	@IBAction func okApropos(_ sender: NSView!) {
		if useModalPanels {
			sender.window?.orderOut(self)
		}
		
		if sender.window!.level == .modalPanel {
			NSApp.stopModal(withCode: .OK)
		} else {
			openAproposFromPanel()
		}
	}
	
	@IBAction func okText(_ sender: NSView!) {
		if useModalPanels {
			sender.window?.orderOut(self)
		}
		
		if sender.window!.level == .modalPanel {
			NSApp.stopModal(withCode: .OK)
		} else {
			openTitleFromPanel()
		}
	}
	
	@IBAction func cancelText(_ sender: NSView!) {
		sender.window?.orderOut(self)
		if sender.window!.level == .modalPanel {
			NSApp.stopModal(withCode: .cancel)
		}
	}
	
	// MARK: Methods to do the services entries
	
	@objc func openFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
		guard let types = pboard.types else {
			return
		}
		if types.contains(.fileURL),
		   let fileArray = pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
			for tmpPath in fileArray {
				openDocument(withContentsOf: tmpPath, display: true, completionHandler: { (doc, display, error) in
					//Swift.print("document: '\(String(describing: doc))', Display: \(display), Error '\(String(describing: error))'")
				})
			}
		}
	}
	
	@objc func openSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
		if let types = pboard.types,
		   types.contains(.string),
		   let pboardString = pboard.string(forType: .string) {
			openString(pboardString)
		}
	}
	
	@objc func openApropos(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
		if let types = pboard.types,
			types.contains(.string),
			let pboardString = pboard.string(forType: .string) {
			openApropos(pboardString)
		}
	}
}

private func isSectionWord(_ word: String) -> Bool
{
	if word.isEmpty {
		return false
	}
	if CharacterSet.decimalDigits.contains(word.unicodeScalars.first!) {
		return true
	}
	if word == "n" {
		return true
	}
	return false
}

private func getWordArray(_ string: String) -> [String] {
	let spaceSet = CharacterSet.whitespacesAndNewlines
	let nonspaceSet = spaceSet.inverted
	var wordArray = [String]()
	let scanner = Scanner(string: string)
	
	scanner.charactersToBeSkipped = spaceSet
	
	while !scanner.isAtEnd {
		var aWord: NSString? = nil
		if scanner.scanCharacters(from: nonspaceSet, into: &aWord),
			let bWord = aWord as String? {
			wordArray.append(bWord)
		}
	}
	
	return wordArray
}

/// On MacOS X, implement our x-man-page: scheme handler
@objc(ManOpenURLHandlerCommand) @MainActor
class ManOpenURLHandlerCommand : NSScriptCommand {
	/*
	* Terminal seems to accept URLs of the form x-man-page://ls , which means
	* the man page name is essentially the "host" portion, and is passed
	* as an argument to the man(1) command.  The double slash is necessary.
	* Terminal accepts a path portion as well, and will take the first path
	* component and add it to the command as a second argument.  Any other
	* path components are ignored.  Thus, x-man-page://3/printf opens up
	* printf(3), and x-man-page://printf/ls opens both printf(1) and ls(1).
	*
	* We make sure to accept all these forms, and maybe some others.  We'll
	* use all path components, and not require the "//" portion.  We'll build
	* up a string and pass it to our -openString:, which wants things like
	* "printf(3) ls pwd".
	*/
	override func performDefaultImplementation() -> Any? {
		guard let param = directParameter as? String else {
			return nil
		}
		
		let paramRange = param.range(of: URL_SCHEME_PREFIX, options: [.caseInsensitive, .anchored])
		var pageNames = [String]()
		
		if let aRange = paramRange {
			let path = param[aRange.upperBound...]
			let components = (path as NSString).pathComponents
			
			var section: String? = nil
			for name in components {
				if name.isEmpty || name == "" || name == "/" {
					continue
				}
				if isSectionWord(name) {
					section = name
				} else {
					pageNames.append(name)
					if let bSection = section {
						pageNames.append("(\(bSection))")
						section = nil
					}
				}
			}
			
			if pageNames.count > 0 {
				(ManDocumentController.shared as! ManDocumentController).openString(pageNames.joined(separator: " "))
			}
		}
		
		return nil
	}
}
