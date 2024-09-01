//
//  Data+Utils.swift
//  ManOpen
//
//  Created by C.W. Betts on 9/15/16.
//
//

import Foundation

/// compress(1) header
private let compressHeader: [UInt8] = [0o037, 0o235]
/// gzip(1) header
private let gzipHeader: [UInt8] = [0o037, 0o213]
//let rtfStart = "{\\rtf".data(using: String.Encoding.ascii)!
private let rtfStart: [UInt8] = [0x7B, 0x5C, 0x72, 0x74, 0x66]

extension Data {
	/// Checks the data to see if it looks like the start of an nroff file.
	/// Derived from logic in FreeBSD's **file(1)** command.
	public var isNroffData: Bool {
		return (self as NSData).isNroffData
	}
	
	public var isRTFData: Bool {
		return starts(with: rtfStart)
	}
	
	public var isGzipData: Bool {
		return starts(with: compressHeader) || starts(with: gzipHeader)
	}
	
	/// Very rough check -- see if more than a third of the first 100 bytes 
	/// have the high bit set
	public var isBinaryData: Bool {
		let checklen = Swift.min(100, count)
		var badByteCount = 0
		
		if checklen == 0 {
			return false
		}
		
		for byte in self[startIndex..<(startIndex+checklen)] {
			if byte == 0 || (byte & 0x80) != 0 /* !isascii(Int32(byte))*/ {
				badByteCount += 1
			}
		}
		
		return badByteCount > 0 && (checklen / badByteCount) <= 2;
	}
}
