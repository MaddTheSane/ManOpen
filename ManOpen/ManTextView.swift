//
//  ManTextView.swift
//  ManOpen
//
//  Created by C.W. Betts on 1/30/15.
//
//

import Cocoa
#if USE_CGCONTEXT_FOR_PRINTING
import CoreText
#endif

class ManTextView: NSTextView {
	override func resetCursorRects() {
		let container = textContainer
		let layout = layoutManager
		let storage = textStorage
		let visible = visibleRect
		var currIndex = 0
		
		super.resetCursorRects()
		
		while currIndex < (storage?.length ?? 0) {
			var currRange = NSRange(location: 0, length: 0)
			let attribs = storage?.attributes(at: currIndex, effectiveRange: &currRange)
			let isLinkSection = attribs?[.link] != nil
			if isLinkSection {
				
				let rects: UnsafeBufferPointer<NSRect> = {
					let ignoreRange = NSRange.notFound
					var rectCount = 0
					let aRec = layout!.rectArray(forCharacterRange: currRange, withinSelectedCharacterRange: ignoreRange, in: container!, rectCount: &rectCount)
					return UnsafeBufferPointer(start: aRec, count: rectCount)
				}()
				
				
				for aRect in rects {
					if aRect.intersects(visible) {
						addCursorRect(aRect, cursor: .pointingHand)
					}
				}
			}
			currIndex = currRange.upperBound
		}
	}
	
	func scrollToTop(of charRange: NSRange) {
		let layout = layoutManager!
		let glyphRange = layout.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
		var rect = layout.boundingRect(forGlyphRange: glyphRange, in: textContainer!)
		let height = visibleRect.height
		
		if height > 0 {
			rect.size.height = height
		}
		
		scrollToVisible(rect)
	}
	
	/// Make space page down (and shift/alt-space page up)
	override func keyDown(with event: NSEvent) {
		if event.charactersIgnoringModifiers == " " {
			if event.modifierFlags.contains(.option) || event.modifierFlags.contains(.shift) {
				pageUp(self)
			} else {
				pageDown(self)
			}
		} else {
			super.keyDown(with: event)
		}
	}
	
	
	/// Draw page numbers when printing. Under early versions of MacOS X... the normal
	/// NSString drawing methods don't work in the context of this method. So, I fell back on
	/// CoreGraphics primitives, which did. However, I'm now just supporting Tiger (10.4) and up,
	/// and it looks like the bugs have been fixed, so we can just use the higher-level
	/// NSStringDrawing now, thankfully.
	override func drawPageBorder(with borderSize: NSSize) {
		let font = UserDefaults.standard.manFont
		
		let currPage = NSPrintOperation.current!.currentPage
		let pageString = "\(currPage)"
		let style = NSMutableParagraphStyle()
		var drawAttribs = [NSAttributedString.Key: Any]()
		
		style.alignment = .center
		drawAttribs[.paragraphStyle] = style.copy()
		drawAttribs[.font] = font
		#if !USE_CGCONTEXT_FOR_PRINTING
			let drawRect = NSRect(x: 0, y: 0, width: borderSize.width, height: 20 + font.ascender)
			
			pageString.draw(in: drawRect, withAttributes: drawAttribs)
		#else
			let strWidth = pageString.size(withAttributes: drawAttribs).width
			let point = NSPoint(x: borderSize.width/2 - strWidth/2, y: 20.0)
			let context = NSGraphicsContext.current!.cgContext
			context.saveGState()
			context.textMatrix = CGAffineTransform.identity
			context.setTextDrawingMode(.fill)  //needed?
			context.setFillColor(gray: 0.0, alpha: 1.0)
						
			context.setFont(CGFont(font.fontName as NSString)!)
			context.setFontSize(font.pointSize)
			let ctfont = CTFontCreateWithName(font.fontName as NSString, font.pointSize, nil)
			let ctDict: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): ctfont]
			let attrStr = NSAttributedString(string: pageString, attributes: ctDict)
			context.textPosition = point
			let line = CTLineCreateWithAttributedString(attrStr)

			// Core Text uses a reference coordinate system with the origin on the bottom-left
			// flip the coordinate system before drawing or the text will appear upside down
			context.translateBy(x: 0, y: borderSize.height)
			context.scaleBy(x: 1.0, y: -1.0)
			
			CTLineDraw(line, context)
			
			context.restoreGState()
		#endif
	}
}

