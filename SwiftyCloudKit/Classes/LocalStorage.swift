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

public struct LocalStorageError: Error {
    public let description: String
}

class LocalStorage {
	let archiveURL: URL
	
	init(archiveName: String) {
		archiveURL = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!.appendingPathComponent(archiveName)
	}
	
    func save(record: CKRecord) -> Bool {
        var localRecords = load()
        
        localRecords.append(record)
        let completedSave = NSKeyedArchiver.archiveRootObject(localRecords, toFile: archiveURL.path)
        print("Save of local record completed sucessfully: \(completedSave)")
        
        return completedSave
    }
    
     func delete(record: CKRecord) -> Bool {
        var localRecords = load()
        
        if let index = localRecords.index(where: { $0.recordID == record.recordID }) {
            localRecords.remove(at: index)
            let completedDelete = NSKeyedArchiver.archiveRootObject(localRecords, toFile: archiveURL.path)
            print("Deletion of local record completed sucessfully: \(completedDelete)")
            
            return completedDelete
        }
        
        return false
    }
    
    func erase() {
        if !load().isEmpty {
            let completed = NSKeyedArchiver.archiveRootObject([], toFile: archiveURL.path)
            print("Ereasing of local storage records completed sucessfully: \(completed)")
        }
    }
    
    func load() -> [CKRecord] {
        guard let records = NSKeyedUnarchiver.unarchiveObject(withFile: archiveURL.path) as? [CKRecord] else {
            return []
        }
        
        return records
    }
}
