//
//  ManTextView.swift
//  ManOpen
//
//  Created by C.W. Betts on 1/30/15.
//
//

import Cocoa
import SwiftAdditions
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
			var attribs = storage?.attributes(at: currIndex, effectiveRange: &currRange)
			let isLinkSection = attribs?[NSLinkAttributeName] != nil
			if isLinkSection {
				let ignoreRange = NSRange.notFound
				var rectCount = 0
				
				let rects: UnsafeBufferPointer<NSRect> = {
					let aRec = layout!.rectArray(forCharacterRange: currRange, withinSelectedCharacterRange: ignoreRange, in: container!, rectCount: &rectCount)
					return UnsafeBufferPointer(start: aRec, count: rectCount)
				}()
				
				
				for aRect in rects {
					if aRect.intersects(visible) {
						addCursorRect(aRect, cursor: NSCursor.pointingHand())
					}
				}
			}
			currIndex = currRange.max;
		}
	}
	
	func scrollRangeToTop(_ charRange: NSRange) {
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
		
		let currPage = NSPrintOperation.current()!.currentPage
		let pageString = "\(currPage)"
		let style = NSParagraphStyle.default().mutableCopy() as! NSMutableParagraphStyle
		var drawAttribs = [String: AnyObject]()
		
		style.alignment = .center
		drawAttribs[NSParagraphStyleAttributeName] = style
		drawAttribs[NSFontAttributeName] = font
		#if !USE_CGCONTEXT_FOR_PRINTING
			let drawRect = NSRect(x: 0, y: 0, width: borderSize.width, height: 20 + font.ascender)
			
			(pageString as NSString).draw(in: drawRect, withAttributes: drawAttribs)
		#else
			let strWidth = (pageString as NSString).sizeWithAttributes(drawAttribs).width
			let point = NSPoint(x: borderSize.width/2 - strWidth/2, y: 20.0)
			let context = NSGraphicsContext.currentContext()!.CGContext
			CGContextSaveGState(context);
			CGContextSetTextMatrix(context, CGAffineTransformIdentity);
			CGContextSetTextDrawingMode(context, .Fill);  //needed?
			CGContextSetGrayFillColor(context, 0.0, 1.0);
						
			CGContextSetFont(context, CGFontCreateWithFontName(font.fontName))
			CGContextSetFontSize(context, font.pointSize)
			let ctfont = CTFontCreateWithName(font.fontName, font.pointSize, nil)
			let ctDict = [kCTFontAttributeName as String: ctfont]
			let attrStr = NSAttributedString(string: pageString, attributes: ctDict)
			CGContextSetTextPosition(context, point.x, point.y)
			let line = CTLineCreateWithAttributedString(attrStr)

			// Core Text uses a reference coordinate system with the origin on the bottom-left
			// flip the coordinate system before drawing or the text will appear upside down
			CGContextTranslateCTM(context, 0, borderSize.height);
			CGContextScaleCTM(context, 1.0, -1.0);
			
			CTLineDraw(line, context)
			
			CGContextRestoreGState(context);
		#endif
	}
}

