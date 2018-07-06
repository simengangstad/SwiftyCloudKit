// Local storage of CKRecords
//
//
//  LocalStorage.swift
//  Pods
//
//  Created by Simen Gangstad on 01.04.2018.
//

import Foundation
import CloudKit
import UIKit

public struct LocalStorageError: Error {
    public let description: String
}

public class LocalStorage {
	
	public let archiveName: String
	
	public var directory: URL {
		let paths = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
		return paths[0].appendingPathComponent(archiveName, isDirectory: true)
	}
	
	public var archiveURL: URL {
		return directory.appendingPathComponent("data")
	}
	
	private let SystemField = "system"
	
	public init(archiveName: String) {
		self.archiveName = archiveName
		createDirectory()
	}
	
	@discardableResult
    public func save(record: CKRecord) -> Bool {
		var map = retrieveMap()
		
		let archivedData = NSMutableData()
		let archiver = NSKeyedArchiver(forWritingWith: archivedData)
		archiver.requiresSecureCoding = true
		record.encodeSystemFields(with: archiver)
		archiver.finishEncoding()
		map[record.recordID] = [SystemField : archivedData as Data]
		
		for key in record.allKeys() {
			if let value = record[key] as? CKAsset {
				if let data = try? Data(contentsOf: value.fileURL) {
					let fileName: String = "\(record.recordID.recordName)_\(key)"
					do {
						try data.write(to: directory.appendingPathComponent(fileName))
						map[record.recordID]!["cka_\(key)"] = fileName
					}
					catch let error {
						print(error)
					}
				}
			}
			else {
				map[record.recordID]![key] = record[key]
			}
		}
		
		let completedSave = NSKeyedArchiver.archiveRootObject(map, toFile: archiveURL.path)
        print("Save of local record completed sucessfully: \(completedSave)")
        
        return completedSave
    }
	
	@discardableResult
	public func delete(record: CKRecord) -> Bool {
        var map = retrieveMap()
		
		if map.contains(where: { $0.key == record.recordID }) {
			for (key, value) in map[record.recordID]! {
				if key.hasPrefix("cka_") {
					do {
						try FileManager.default.removeItem(at: directory.appendingPathComponent(value as! String))
					}
					catch let error {
						print(error)
					}
				}
			}
			
			map.removeValue(forKey: record.recordID)
		}
		
		let completedDelete = NSKeyedArchiver.archiveRootObject(map, toFile: archiveURL.path)
		print("Deletion of local record completed sucessfully: \(completedDelete)")
		
		return completedDelete
    }

	public func createDirectory() {
		var isDirectory: ObjCBool = ObjCBool(false)
		guard !FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
			return
		}
		
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: nil)
		}
		catch let error {
			print(error)
		}
	}
	
	public func eraseDirectory() {
		do {
			try FileManager.default.removeItem(at: directory)
		}
		catch let error {
			print(error)
		}
	}
	
    public func eraseContentOfDirectory() {
		do {
			for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles) {
				try FileManager.default.removeItem(at: file)
			}
		}
		catch let error {
			print(error)
		}
    }
	
	private func retrieveMap() -> [CKRecord.ID: [String : Any]] {
		guard let map = NSKeyedUnarchiver.unarchiveObject(withFile: archiveURL.path) as? [CKRecord.ID: [String : Any]] else {
			return [:]
		}
		
		return map
	}
    
    public func load() -> [CKRecord] {
        guard let map = NSKeyedUnarchiver.unarchiveObject(withFile: archiveURL.path) as? [CKRecord.ID: [String : Any]] else {
			return []
        }
		
		var records: [CKRecord] = []
		
		for (_, var fields) in map {
			let unarchiver = NSKeyedUnarchiver(forReadingWith: fields[SystemField] as! Data)
			unarchiver.requiresSecureCoding = true
			if let record = CKRecord(coder: unarchiver) {
				fields.removeValue(forKey: SystemField)
				
				for (var key, value) in fields {
					if key.hasPrefix("cka_") {
						key = String(key[key.index(key.startIndex, offsetBy: 4)..<key.endIndex])
						record[key] = CKAsset(fileURL: directory.appendingPathComponent(value as! String))
					}
					else {
						record[key] = value as? CKRecordValue
					}
				}
				
				records.append(record)
			}
		}
		
        return records
    }
}
