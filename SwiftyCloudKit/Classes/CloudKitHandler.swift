import CloudKit

@available(iOS 10.0, *)
protocol CloudKitHandler: CloudKitErrorHandler {
    var database: CKDatabase { get }

    func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?)
    func delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?) -> Void)?)
}

@available(iOS 10.0, *)
extension CloudKitHandler {
    public func upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?) {
        database.save(record) { [unowned self] (savedRecord, error) in
            if let error = error as? CKError {
                self.handleCloudKitError(error: error)
                self.retryUploadAfterError(error: error, withRecord: record, andCompletionHandler: completionHandler)
            }
            else {
                completionHandler?(savedRecord)
            }
        }
    }

    public func retryUploadAfterError(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecord?) -> Void)?) {
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
                self.handleCloudKitError(error: error)
                self.retryDeletionAfterError(error: error, withRecord: record, andCompletionHandler: completionHandler)
            }
            else {
                completionHandler?(deletedRecordID)
            }
        }
    }

    public func retryDeletionAfterError(error: Error?, withRecord record: CKRecord, andCompletionHandler completionHandler: ((CKRecordID?) -> Void)?) {
        if let retryInterval = (error as? CKError)?.userInfo[CKErrorRetryAfterKey] as? TimeInterval {
            DispatchQueue.main.async {
                Timer.scheduledTimer(withTimeInterval: retryInterval, repeats: false) { [unowned self] (timer) in
                    self.delete(record: record, withCompletionHandler: completionHandler)
                }
            }
        }
    }
}
