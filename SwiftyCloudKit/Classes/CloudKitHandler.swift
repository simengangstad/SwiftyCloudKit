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
     Uploads a CKRecord to a given database.
     
     - parameters:
         - record: Record to upload
         - database: Database to upload to
         - completionHandler: Is fired after an upload attempt
     
     - important: The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to upload to iCloud or save locally.
     */
    func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?)
    
    /**
     Deletes a CKRecord from a given database.
     
     - parameters:
         - record: Record to delete
         - completionHandler: Is fired after a deletion attempt
     
     - important: The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI. If the method fails the completion handler can either include a CKError or a LocalStorageError depending on whether it failed to delete from iCloud or delete from local storage.
     */
    func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?)
}

@available (iOS 10.0, tvOS 10.0, OSX 10.12, *)
public extension CloudKitHandler {

    public func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?) {
        database.save(record) { [unowned self] (savedRecord, error) in
            
            if let error = error {
                if Reachability.isConnectedToNetwork(), let error = error as? CKError {
                    self.retryUploadAfter(error: error, withRecord: record, andCompletionHandler: completionHandler)
                    return
                }
                else if offlineSupport {
                    print("Upload failed, saving locally...")
                    if !LocalStorage.save(localRecord: record) {
                        completionHandler?(nil, error)
                        return
                    }
                }
            }
            
            completionHandler?(savedRecord != nil ? savedRecord : record, error)
        }
    }
    
    /**
     Will set up to retry the upload after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the upload function again with the same arguments.
     
     - parameters:
         - error: Rrror causing the record upload to fail
         - record: Record which the handler will try to upload again
         - database: The database we will retry to upload to
         - completionHandler: Completion handler given to the upload function
     */
    public func retryUploadAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.upload(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
    

    public func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?) {
        let localRecords = LocalStorage.loadLocalRecords()
        
        // If the record to be deleted exist in the local records
        if offlineSupport, let index = localRecords.index(where: { $0.recordID == record.recordID }) {
            let localRecord = localRecords[index]
            if LocalStorage.delete(localRecord: localRecord) {
                completionHandler?(localRecord.recordID, nil)
            }
            else {
                completionHandler?(nil, LocalStorageError(description: "Could not delete local record..."))
            }
        }
        else {
            database.delete(withRecordID: record.recordID) { [unowned self] (deletedRecordID, error) in
                if let error = error as? CKError {
                    self.retryDeletionAfter(error: error, withRecord: record, andCompletionHandler: completionHandler)
                    return
                }
                
                completionHandler?(deletedRecordID, error)
            }
        }
    }

    /**
     Will set up to retry the deletion after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls the delete function again with the same arguments.
     
     - parameters:
         - error: The error causing the record deletion to fail
         - record: The record which the handler will try to delete again
         - completionHandler: The completion handler given to the delete function
     */
    func retryDeletionAfter(error: CKError?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?) {
        if let retryInterval = error?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
}
