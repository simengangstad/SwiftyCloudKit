import CloudKit

/**
 The protocol defining upload and delete operations to and from iCloud.
 */
@available(iOS 10.0, *)
public protocol CloudKitHandler: CloudKitErrorHandler {
    /**
     The database the handler uploads to and deletes from.
    */
    var database: CKDatabase { get }

    /**
     Uploads a CKRecord to the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to upload.
        - completionHandler: Is fired when the record is uploaded and includes it in the parameters. If an error occurred during
                             the operation the handle(cloudKitError error: CKError) from the CloudKitErrorHandler is called.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI.
     */
    func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?)
    
    /**
     Deletes a CKRecord from the specified database conformed in the protocol.
     
     - parameters:
        - record: The record to delete.
        - completionHandler: Is fired when the record is deleted and includes its recordID in the parameters. If an error occurred during
                             the operation the handle(cloudKitError error: CKError) from the CloudKitErrorHandler is called.
     
     - important:
     The completion handler is called from a global asynchronous thread, switch to the main queue before making changes to e.g. the UI.
     */
    func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?) -> Void)?)
}

@available(iOS 10.0, *)
public extension CloudKitHandler {
    public func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?) {
        database.save(record) { [unowned self] (savedRecord, error) in
            if let error = error as? CKError {
                self.handle(cloudKitError: error)
                self.retryUploadAfter(error: error, withRecord: record, andCompletionHandler: completionHandler)
            }
            else {
                completionHandler?(savedRecord)
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
    public func retryUploadAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?) -> Void)?) {
        if let retryInterval = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.upload(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }

    public func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?) -> Void)?) {
        database.delete(withRecordID: record.recordID) { (deletedRecordID, error) in
            if let error = error as? CKError {
                self.handle(cloudKitError: error)
                self.retryDeletionAfter(error: error, withRecord: record, andCompletionHandler: completionHandler)
            }
            else {
                completionHandler?(deletedRecordID)
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
    public func retryDeletionAfter(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?) -> Void)?) {
        if let retryInterval = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
}
