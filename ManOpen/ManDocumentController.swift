//
//  ManDocumentController.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/8/14.
//
//

import Cocoa
import SwiftAdditions

private let MAN_BINARY = "/usr/bin/man"
//#define MANPATH_FORMAT @" -m '%@'"  // There's a bug in man(1) on OSX and OSXS
private let MANPATH_FORMAT = " -M '%@'"

func EscapePath(_ path: String, addSurroundingQuotes: Bool = false) -> String {
	var modPath = path
	if path.range(of: "'") != nil {
		var newString = ""
		let scanner = Scanner(string: path)
		
		scanner.charactersToBeSkipped = nil
		
		while !scanner.isAtEnd {
			var betweenString: NSString? = nil
			if scanner.scanUpTo("'", into: &betweenString) {
				if let aBetweenString = betweenString {
					newString += aBetweenString as String
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

@NSApplicationMain
class ManDocumentController: NSDocumentController, NSApplicationDelegate {
	@IBOutlet weak var helpScrollView: NSScrollView!
	@IBOutlet weak var openTextPanel: NSPanel!
	@IBOutlet weak var aproposPanel: NSPanel!
	@IBOutlet weak var helpPanel: NSPanel!
	@IBOutlet weak var aproposField: NSTextField!
	@IBOutlet weak var openTextField: NSTextField!
	@IBOutlet weak var openSectionPopup: NSPopUpButton!
	var startedUp = false
	fileprivate var nibObjects = [AnyObject]()
	private var bridge: ManBridgeCallback? = nil
	
	private final class ManOpenXPC: NSObject, ManOpenProtocol {
		weak var controller: ManDocumentController?
		func openName(_ name: String, section: String?, manPath: String?, forceToFront force: Bool) {
			runOnMainThreadAsync {
				self.controller?.openName(name, section: section, manPath: manPath, forceToFront: force)
			}
		}
		
		func openApropos(_ apropos: String, manPath: String?, forceToFront force: Bool) {
			runOnMainThreadAsync {
				self.controller?.openApropos(apropos, manPath: manPath, forceToFront: force)
			}
		}
		
		func openFile(_ filename: String, forceToFront force: Bool) {
			runOnMainThreadAsync {
				self.controller?.openFile(filename, forceToFront: force)
			}
		}
	}
	
	func ensureActive() {
		if !NSApplication.shared.isActive {
			NSApplication.shared.activate(ignoringOtherApps: true)
		}
	}
	
	@objc func openName(_ name: String, section: String? = nil, manPath: String? = nil, forceToFront force: Bool = true) {
		if force {
			ensureActive()
		}
		openDocument(name: name, section: section, manPath: manPath ?? UserDefaults.standard.manPath)
	}
	
	@objc func openApropos(_ apropos: String, manPath: String? = nil, forceToFront force: Bool = true) {
		if force {
			ensureActive()
		}
		
		openAproposDocument(apropos, manPath: manPath ?? UserDefaults.standard.manPath)
	}
	
	@objc func openFile(_ filename: String, forceToFront force: Bool = true) {
		if force {
			ensureActive()
		}
		
		openDocument(withContentsOf: URL(fileURLWithPath: filename), display: true) { (doc, wasOpened, error) -> Void in
			//What to do??
		}
	}
	
	var useModalPanels: Bool {
		return !(UserDefaults.standard[kKeepPanelsOpen]!)
	}
	
	func applicationDidFinishLaunching(_ notification: Notification) {
		NSApp.servicesProvider = self
		openTextPanel.setFrameUsingName(NSWindow.FrameAutosaveName(rawValue: "OpenTitlePanel"))
		openTextPanel.setFrameAutosaveName(NSWindow.FrameAutosaveName(rawValue: "OpenTitlePanel"))
		aproposPanel.setFrameUsingName(NSWindow.FrameAutosaveName(rawValue: "AproposPanel"))
		aproposPanel.setFrameAutosaveName(NSWindow.FrameAutosaveName(rawValue: "AproposPanel"))
		
		startedUp = true
	}
	
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
		
		if let manPath = manPath, !manPath.isEmpty {
			command += " -M '\(EscapePath(manPath))'"
		}
		
		return command
	}
	
	func dataByExecutingCommand(_ command: String, maxLength: Int = 0, extraEnv: Dictionary<String, String>? = nil) -> Data? {
		let pipe = Pipe()
		let task = Process()
		var output: Data?
		
		if let anExtraEnv = extraEnv {
			var environment = ProcessInfo.processInfo.environment
			environment += anExtraEnv
			task.environment = environment
		}
		
		task.launchPath = "/bin/sh"
		task.arguments = ["-c", command]
		task.standardOutput = pipe
		task.standardError = FileHandle.nullDevice
		task.qualityOfService = .userInitiated
		task.launch()
		
		if maxLength > 0 {
			output = pipe.fileHandleForReading.readData(ofLength: maxLength)
			task.terminate()
		} else {
			output = try? pipe.fileHandleForReading.readDataToEndOfFileIgnoreInterrupt()
		}
		task.waitUntilExit()
		
		return output
	}
	
	func dataByExecutingCommand(_ command: String, manPath: String) -> Data? {
		return dataByExecutingCommand(command, extraEnv: ["MANPATH" : manPath])
	}
	
	func manFile(name: String, section: String? = nil, manPath: String? = nil) -> String? {
		var command = manCommand(manPath: manPath)
		let spaceString = ""
		command += " -w \(section ?? spaceString) \(name)"
		if let data = dataByExecutingCommand(command) {
			if data.count <= 0 {
				return nil
			}
			
			let manager = FileManager.default
			var len = data.count
			let ptr = (data as NSData).bytes
			
			let newlinePtr = memchr(ptr, 0x0A, len) // 0A is == '\n'
			
			if let newlinePtr = newlinePtr {
				len = ptr.distance(to: newlinePtr)
			}
			
			let filename = manager.string(withFileSystemRepresentation: ptr.assumingMemoryBound(to: Int8.self), length: len)
			if manager.fileExists(atPath: filename) {
				return filename
			}
		}
		return nil
	}
	
	func typeFromURL(_ url: URL) -> String? {
		let manager = FileManager.default
		var catType = "cat"
		var manType = "man"
		let attributes = try? manager.attributesOfItem(atPath: (url.path as NSString).resolvingSymlinksInPath)
		var len: UInt64
		if let anAttrib = attributes {
			if let tmplen = anAttrib[FileAttributeKey.size] as? NSNumber {
				len = tmplen.uint64Value
			} else {
				len = 0
			}
		} else {
			len = 0
		}
		let maxLength = min(150, len)
		
		if maxLength == 0 {
			return catType
		}
		
		if let handle = try? FileHandle(forReadingFrom: url) {
			var fileHeader = handle.readData(ofLength: Int(maxLength))
			
			if len > 1000000 {
				return nil
			}
			
			if fileHeader.isGzipData {
				let command = "/usr/bin/gzip -dc '\(EscapePath(url.path))'"
				fileHeader = dataByExecutingCommand(command, maxLength: Int(maxLength))!
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
	
	override func openDocument(withContentsOf url: URL, display displayDocument: Bool, completionHandler: (@escaping (NSDocument?, Bool, Error?) -> Void)) {
		let standardizedURL = url.standardized
		var error: Error? = nil
		let numDocuments = documents.count
		
		var document = self.document(for: standardizedURL)
		if document == nil {
			if let type = typeFromURL(standardizedURL) {
				do {
					document = try makeDocument(withContentsOf: standardizedURL, ofType: type)
					document!.makeWindowControllers()
					addDocument(document!)
				} catch let anErr {
					error = anErr
				}
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
	
	override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
		return openPanel.runModal().rawValue
	}
	
	func document(forTitle title: String) -> NSDocument? {
		for document in documents {
			if let manDoc = document as? ManDocument {
				if document.fileURL == nil && manDoc.shortTitle == title {
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
			if helpPath == nil {
				return
			}
		}
		
		(helpScrollView.contentView.documentView as! NSTextView).readRTFD(fromFile: helpPath!.path)
		
		DispatchQueue.global().async {
			// Set up the one NSXPCListener for this service. It will handle all incoming connections.
			let listener = NSXPCListener.anonymous()
			listener.delegate = self
			
			// Resuming the serviceListener starts this service. This method does not return.
			listener.resume()
		}
	}
	
	@discardableResult
	func openDocument(name: String, section: String? = nil, manPath: String) -> ManDocument? {
		var title = name
		if (section != nil && section!.isEmpty == false) {
			title = "\(name)(\(section!))"
		}
		
		var document = self.document(forTitle: title) as? ManDocument
		if document == nil {
			document = ManDocument(name: name, section: section, manPath: manPath, title: title)
			
			if let filename = manFile(name: name, section: section, manPath: manPath) {
				let afn = (filename as NSString).resolvingSymlinksInPath
				let fileURL = URL(fileURLWithPath: afn)
				noteNewRecentDocumentURL(fileURL)
				document?.fileURL = fileURL
			}
			
			addDocument(document!)
			document?.makeWindowControllers()
		}
		
		document?.showWindows()
		
		return document
	}
	
	@discardableResult
	func openAproposDocument(_ apropos: String, manPath: String) -> AproposDocument? {
		let title = "Apropos \(apropos)"
		var document = self.document(forTitle: title) as? AproposDocument
		
		if document == nil {
			document = AproposDocument(string: apropos, manPath: manPath, title: title)
			
			if let document = document {
				addDocument(document)
			}
			document?.makeWindowControllers()
		}
		
		document?.showWindows()
		
		return document
	}
	
	@discardableResult
	func openWord(_ word: String) -> ManDocument? {
		var base = word
		var section: String? = nil
		let lparenRange = word.range(of: "(")
		let rparenRange = word.range(of: ")")
		
		if let lparenRange = lparenRange, let rparenRange = rparenRange , lparenRange.lowerBound < rparenRange.lowerBound {
			let lp = lparenRange
			let rp = rparenRange
			
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
			alert.informativeText = String(format: NSLocalizedString("This will open approximately %@ windows!", comment: "This will open approximately (the number of) windows!"), locCount)
			alert.addButton(withTitle: NSLocalizedString("Cancel", comment: "Cancel"))
			alert.addButton(withTitle: NSLocalizedString("Continue", comment: "Continue"))
			let aNum = alert.runModal()
			if aNum != .alertSecondButtonReturn {
				return
			}
		}
		
		openString(string, oneWordOnly: false)
	}
	
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
					if let aWord = aWord {
						lastWord = aWord as String
					}
				} else if aWord!.hasPrefix("(") && aWord!.hasSuffix(")") {
					openWord(lastWord + (aWord! as String))
					lastWord = nil
					if oneOnly {
						break
					}
				}
			}
		}
		
		if lastWord != nil {
			if lastWord.hasSuffix(",") {
				var lastIndex = lastWord.endIndex
				lastWord = String(lastWord[lastWord.startIndex..<lastIndex])
				lastIndex = lastWord.index(before: lastIndex)
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
		
		/*
		* Set ourselves up for DO connections.  I do it here so it's done as
		* early as possible.  If the command-line tool still has problems
		* connecting, we may be able to do this whole thing in main()...
		*/
		
		bridge = ManBridgeCallback(manDocumentController: self)
		
		PrefPanelController.registerManDefaults()
		var tmpNibArray: NSArray? = nil
		Bundle.main.loadNibNamed(NSNib.Name(rawValue: "DocController"), owner: self, topLevelObjects: &tmpNibArray)
		
		nibObjects = tmpNibArray as [AnyObject]? ?? []
	}
	
	required init(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
	
	func openTitleFromPanel() {
		var aString = openTextField.stringValue
		var words = getWordArray(aString)
		
		/* If the string is of the form "3 printf", arrange it better for our parser.  Requested by Eskimo.  Also accept 'n' as a section */
		if words.count == 2 && aString.range(of: "(") == nil && isSectionWord(words[0]) {
			aString = "\(words[1])(\(words[0]))"
		}
		
		/* Append the section if chosen in the popup and not explicity defined in the string */
		if aString.characters.count > 0 && openSectionPopup.indexOfSelectedItem > 0 && aString.range(of: "(") == nil {
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
		
		if sender.window!.level == NSWindow.Level.modalPanel {
			NSApp.stopModal(withCode: .OK)
		} else {
			openAproposFromPanel()
		}
	}
	
	@IBAction func okText(_ sender: NSView!) {
		if useModalPanels {
			sender.window?.orderOut(self)
		}
		
		if sender.window!.level == NSWindow.Level.modalPanel {
			NSApp.stopModal(withCode: .OK)
		} else {
			openTitleFromPanel()
		}
	}
	
	@IBAction func cancelText(_ sender: NSView!) {
		sender.window?.orderOut(self)
		if sender.window!.level == NSWindow.Level.modalPanel {
			NSApp.stopModal(withCode: .cancel)
		}
	}
	
	// MARK: Methods to do the services entries
	
	@objc func openFiles(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
		guard let types = pboard.types else {
			return
		}
		if types.contains(ourFile), let fileArray = pboard.propertyList(forType: ourFile) as? [String] {
			for tmpPath in fileArray {
				openDocument(withContentsOf: URL(fileURLWithPath: tmpPath), display: true, completionHandler: { (doc, display, error) in
					//Swift.print("document: '\(String(describing: doc))', Display: \(display), Error '\(String(describing: error))'")
				})
			}
		}
	}
	
	@objc func openSelection(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString?>?) {
		if let types = pboard.types, types.contains(.string), let pboardString = pboard.string(forType: .string) {
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

extension ManDocumentController: NSXPCListenerDelegate {
	func listener(_ listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
		// This method is where the NSXPCListener configures, accepts, and resumes a new incoming NSXPCConnection.
		
		// Configure the connection.
		// First, set the interface that the exported object implements.
		newConnection.exportedInterface = NSXPCInterface(with: ManOpenProtocol.self)
		
		// Next, set the object that the connection exports. All messages sent on the connection to this service will be sent to the exported object to handle. The connection retains the exported object.
		let exportedObject = ManOpenXPC()
		exportedObject.controller = self
		newConnection.exportedObject = exportedObject
		
		// Resuming the connection allows the system to deliver more incoming messages.
		newConnection.resume()
		
		// Returning YES from this method tells the system that you have accepted this connection. If you want to reject the connection for some reason, call -invalidate on the connection and return NO.
		return true;
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
		if scanner.scanCharacters(from: nonspaceSet, into: &aWord) {
			wordArray.append(aWord! as String)
		}
	}
	
	return wordArray
}

@objc(ManOpenURLHandlerCommand)
class ManOpenURLHandlerCommand : NSScriptCommand {
	override func performDefaultImplementation() -> Any? {
		guard let param = directParameter as? String else {
			return nil
		}
		
		let paramRange = param.range(of: URL_SCHEME_PREFIX, options: [.caseInsensitive, .anchored])
		var pageNames = [String]()
		
		if let aRange = paramRange {
			let path = param[aRange.upperBound...]
			let components = (path as NSString).pathComponents
			
			for name in components {
				var section: String? = nil
				if name.characters.count == 0 || name == "" {
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
