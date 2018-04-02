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
    static let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
    static let ArchiveURL = DocumentsDirectory.appendingPathComponent("records")
    
    class func save(localRecord: CKRecord) -> Bool {
        var localRecords = loadLocalRecords()
        
        print("Attempting to save record locally... \(localRecord)")
        localRecords.append(localRecord)
        
        let completedSave = NSKeyedArchiver.archiveRootObject(localRecords, toFile: ArchiveURL.path)
        print("Save completed sucessfully: \(completedSave)")
        
        return completedSave
    }
    
    class func delete(localRecord: CKRecord) -> Bool {
        var localRecords = loadLocalRecords()
        
        if let index = localRecords.index(where: { $0.recordID == localRecord.recordID }) {
            print("Attempting to delete local record... \(localRecord)")
            localRecords.remove(at: index)
            
            let completedDelete = NSKeyedArchiver.archiveRootObject(localRecords, toFile: ArchiveURL.path)
            print("Deletion completed sucessfully: \(completedDelete)")
            
            return completedDelete
        }
        
        return false
    }
    
    class func eraseLocalRecords() {
        if !loadLocalRecords().isEmpty {
            let completed = NSKeyedArchiver.archiveRootObject([], toFile: ArchiveURL.path)
            print("Attempting to erease local records...")
            print("Ereasing completed sucessfully: \(completed)")
        }
    }
    
    class func loadLocalRecords() -> [CKRecord] {
        guard let records = NSKeyedUnarchiver.unarchiveObject(withFile: ArchiveURL.path) as? [CKRecord] else {
            return []
        }
        
        return records
    }
}
