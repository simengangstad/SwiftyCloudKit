//
//  CloudKitHandler.swift
//  Pods
//
//  Created by Simen Gangstad on 01.04.2018.
//

import CloudKit

/**
 Defining upload and delete operations to and from iCloud.
 */
@available (iOS 10.0, tvOS 10.0, OSX 10.12, *)
public protocol CloudKitHandler: AnyObject {
    
    /**
     The database the handler uploads to and deletes from.
     */
    var database: CKDatabase { get }
    
    /**
     Uploads an array of CKRecords to a given database. Will store the records locally until the upload is successful.
     
     - parameters:
         - records: Records to upload
		 - priority: The quality of service for the upload. Defaults to user initiated
		 - perRecordProgress: Fired with information about the upload progress for each record
         - completionHandler: Is fired after an upload attempt
     
     - important: The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to upload to iCloud or save locally.
     */
	func upload(records: [CKRecord], withPriority priority: QualityOfService, perRecordProgress: ((CKRecord, Double) -> Void)?, andCompletionHandler completionHandler: (([CKRecord]?, Error?) -> Void)?)

    /**
     Deletes an array of CKRecords from a given database.
     
     - parameters:
		- records: Records to delete
		- priority: The quality of service for the deletion. Defaults to user initiated
		- perRecordProgress: Fired with information about the deletion progress for each record
		- completionHandler: Is fired after a deletion attempt
     
     - important: The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to delete from iCloud or delete from local storage.
     */
    func delete(records: [CKRecord], withPriority priority: QualityOfService, perRecordProgress: ((CKRecord, Double) -> Void)?, andCompletionHandler completionHandler: (([CKRecord.ID]?, Error?) -> Void)?)
}

@available (iOS 10.0, tvOS 10.0, OSX 10.12, *)
public extension CloudKitHandler {
	
	func upload(records: [CKRecord], withPriority priority: QualityOfService = .userInitiated, perRecordProgress: ((CKRecord, Double) -> Void)? = nil, andCompletionHandler completionHandler: (([CKRecord]?, Error?) -> Void)? = nil) {
		if Reachability.isConnectedToNetwork() {
			// Save records temporarily if the upload fails
			for record in records {
				localStorageSavedRecords.save(record: record)
			}
			
			let modifyOperation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
			modifyOperation.savePolicy = .allKeys
			modifyOperation.qualityOfService = priority
			modifyOperation.perRecordProgressBlock = perRecordProgress
			modifyOperation.modifyRecordsCompletionBlock = { (uploadedRecords, _, error)  in
				if let error = error as? CKError  {
					self.retryUploadAfter(error: error, withRecords: records, andCompletionHandler: completionHandler)
					return
				}
				
				if let uploadedRecords = uploadedRecords {
					for record in uploadedRecords {
						localStorageSavedRecords.delete(record: record)
					}
					
					completionHandler?(uploadedRecords, nil)
				}
				else {
					completionHandler?(nil, nil)
				}
			}
			
			database.add(modifyOperation)
		}
		else if offlineSupport {
			print("No connection detected, saving locally...")
			for record in records {
				if !localStorageSavedRecords.save(record: record) {
					completionHandler?(nil, LocalStorageError(description: "Error saving local record..."))
					return
				}
			}
			
			completionHandler?(records, nil)
		}
		else {
			completionHandler?(nil, CloudKitHandlerError(description: "No internet connection and offlineSupport is not enabled, failed to upload record"))
		}
	}
    
    /**
     Will set up to retry the upload after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the upload function again with the same arguments.
     */
    public func retryUploadAfter(error: CKError?, withRecords records: [CKRecord], priority: QualityOfService = .userInitiated, perRecordProgress: ((CKRecord, Double) -> Void)? = nil, andCompletionHandler completionHandler: (([CKRecord]?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
					self.upload(records: records, withPriority: priority, perRecordProgress: perRecordProgress, andCompletionHandler: completionHandler)
                }
            }
        }
    }
	
	func delete(records: [CKRecord], withPriority priority: QualityOfService = .userInitiated, perRecordProgress: ((CKRecord, Double) -> Void)? = nil, andCompletionHandler completionHandler: (([CKRecord.ID]?, Error?) -> Void)? = nil) {
        let savedLocalRecords = localStorageSavedRecords.load()
		// All the records which aren't stored locally
		var recordsToDelete = records
		
		if offlineSupport {
			for record in records {
				if let index = savedLocalRecords.index(where: { $0.recordID == record.recordID }) {
					let localRecord = savedLocalRecords[index]
					if localStorageSavedRecords.delete(record: localRecord) {
						recordsToDelete.remove(at: recordsToDelete.lastIndex(where: { $0.recordID == localRecord.recordID  })!)
					}
				}
			}
			
			if recordsToDelete.isEmpty {
				completionHandler?(records.map({ $0.recordID }), nil)
			}
		}
		
		if Reachability.isConnectedToNetwork() {
			let modifyOperation = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordsToDelete.map({ $0.recordID }))
			modifyOperation.savePolicy = .allKeys
			modifyOperation.qualityOfService = priority
			modifyOperation.perRecordProgressBlock = perRecordProgress
			modifyOperation.modifyRecordsCompletionBlock = { (_, deletedRecordIDs, error) in
				if let error = error as? CKError  {
					self.retryDeletionAfter(error: error, withRecords: recordsToDelete, andCompletionHandler: completionHandler)
					return
				}
				
				if let deletedRecordIDs = deletedRecordIDs {
					completionHandler?(deletedRecordIDs, nil)
				}
				else {
					completionHandler?(nil, nil)
				}
			}
			
			database.add(modifyOperation)
		}
		else if offlineSupport {
			print("Deletion failed, saving records locally for an attempt later...")
			for record in recordsToDelete {
				if !localStorageDeletedRecords.save(record: record) {
					completionHandler?(nil, LocalStorageError(description: "Error saving local record for deletion later..."))
					return
				}
			}
			
			completionHandler?(recordsToDelete.map({ $0.recordID }), nil)
		}
		else {
			completionHandler?(nil, CloudKitHandlerError(description: "No internet connection and offlineSupport is not enabled, failed to delete record"))
		}
    }

    /**
     Will set up to retry the deletion after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the delete function again with the same arguments.
     */
	func retryDeletionAfter(error: CKError?, withRecords records: [CKRecord], priority: QualityOfService = .userInitiated, perRecordProgress: ((CKRecord, Double) -> Void)? = nil, andCompletionHandler completionHandler: (([CKRecord.ID]?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(records: records, withPriority: priority, perRecordProgress: perRecordProgress, andCompletionHandler: completionHandler)
                }
            }
        }
    }
}

public struct CloudKitHandlerError: Error {
	public let description: String
}
