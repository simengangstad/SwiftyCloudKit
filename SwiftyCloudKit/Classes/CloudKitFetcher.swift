import CloudKit

public protocol CloudKitFetcher: CloudKitErrorHandler {
    var database: CKDatabase { get }
    var query: CKQuery? { get }
    var existingRecords: [CKRecord] { get }
    var interval: Int { get }
    var cursor: CKQueryCursor? { get set }
    var moreToFetch: Bool { get set }

    func fetch()
    func terminatingFetchRequest()
    func parseResult(records: [CKRecord])
}

public extension CloudKitFetcher {

    public func fetch() {
        var operation: CKQueryOperation!
        var array: [CKRecord]!

        // Prevents duplicates
        if cursor == nil && moreToFetch {
            array = [CKRecord]()
        }
        else {
            array = existingRecords
        }

        if cursor == nil {
            guard let query = query else {
                handleCloudKitError(error: CKError(_nsError: NSError(domain: "ck fetch", code: CKError.serviceUnavailable.rawValue, userInfo: nil)))
                terminateFetchRequest()

                return
            }

            operation = CKQueryOperation(query: query)
        }
        else {
            operation = CKQueryOperation(cursor: cursor!)
        }

        operation.resultsLimit = interval
        operation.recordFetchedBlock = { [unowned self] in
            if self.moreToFetch {
                array.append($0)
            }
        }

        operation.queryCompletionBlock = { [unowned self] (cursor, error) in
            if cursor != nil {
                self.cursor = cursor
            }
            else {
                self.moreToFetch = false
            }

            if let error = error as? CKError {
                self.handleCloudKitError(error: error)
                self.terminateFetchRequest()
            }
            else {
                self.parseResult(records: array)
            }
        }

        database.add(operation)
    }
}
