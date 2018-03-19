import CloudKit

/**
 The protocol defining upload and delete operations to and from iCloud.
 */
@available(iOS 10.0, *)
public protocol CloudKitHandler: AnyObject {
    /**
     The database the handler uploads to and deletes from.
    */
    var database: CKDatabase { get }

    /**
     Uploads a CKRecord to the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to upload.
        - completionHandler: Is fired after an upload attempt.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI.
     */
    func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, CKError?) -> Void)?)
    
    func retryUploadAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?, CKError?) -> Void)?)
    
    /**
     Deletes a CKRecord from the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to delete.
        - completionHandler: Is fired after a deletion attempt.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI.
     */
    func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, CKError?) -> Void)?)
    
    func retryDeletionAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?, CKError?) -> Void)?)
}

@available(iOS 10.0, *)
public extension CloudKitHandler {
    
    public func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, CKError?) -> Void)?) {
        database.save(record) { (savedRecord, error) in
            if let completionHandler = completionHandler {
                completionHandler(savedRecord, error as? CKError)
            }
        }
    }

    /**
     Will set up to retry the upload after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?) again with the same arguments.
     
     - parameters:
        - error: The error causing the record upload to fail
        - record: The record which the handler will try to upload again
        - completionHandler: The completion handler given to the upload function
    */
    public func retryUploadAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?, CKError?) -> Void)?) {
        if let retryInterval = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.upload(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }

    public func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, CKError?) -> Void)?) {
        database.delete(withRecordID: record.recordID) { (deletedRecordID, error) in
            if let completionHandler = completionHandler {
                completionHandler(deletedRecordID, error as? CKError)
            }
        }
    }

    /**
     Will set up to retry the deletion after a time interval defined by cloud kit [CKErrorRetryAfterKey](https://developer.apple.com/documentation/cloudkit/ckerrorretryafterkey). This function will effectively just wait a bit before it calls delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?) -> Void)?) again with the same arguments.
     
     - parameters:
        - error: The error causing the record deletion to fail
        - record: The record which the handler will try to delete again
        - completionHandler: The completion handler given to the delete function
     */
    public func retryDeletionAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?, CKError?) -> Void)?) {
        if let retryInterval = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
}
