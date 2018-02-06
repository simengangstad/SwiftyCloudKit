import CloudKit

public protocol CloudKitFetcher: CloudKitErrorHandler, PropertyStoring {
    var database: CKDatabase { get }
    var query: CKQuery? { get }
    var existingRecords: [CKRecord] { get }
    var interval: Int { get }
    var cursor: CKQueryCursor? { get set }

    func fetch()
    func parseResult(records: [CKRecord])
    func terminatingFetchRequest()
}

public enum FetchState {
    case more, none
}

private var fetchKey: UInt8 = 0

public extension CloudKitFetcher {
    
    typealias T = FetchState
    
    public var fetchState: FetchState {
        get { return getAssociatedObject(&fetchKey, defaultValue: .more)}
        set { return setAssociatedObject(&fetchKey, value: newValue)}
    }
    
    public func fetch() {
        var operation: CKQueryOperation!
        var array: [CKRecord]!

        // Prevents duplicates
        if cursor == nil && fetchState == .more {
            array = [CKRecord]()
        }
        else {
            array = existingRecords
        }

        if cursor == nil {
            guard let query = query else {
                handleCloudKitError(error: CKError(_nsError: NSError(domain: "ck fetch", code: CKError.serviceUnavailable.rawValue, userInfo: nil)))
                terminatingFetchRequest()
                return
            }

            operation = CKQueryOperation(query: query)
        }
        else {
            operation = CKQueryOperation(cursor: cursor!)
        }

        operation.resultsLimit = interval
        operation.recordFetchedBlock = { [unowned self] in
            if self.fetchState == .more {
                array.append($0)
            }
        }

        operation.queryCompletionBlock = { [unowned self] (cursor, error) in
            if cursor != nil {
                self.cursor = cursor
            }
            else {
                self.fetchState = .none
            }

            if let error = error as? CKError {
                self.handleCloudKitError(error: error)
                self.terminatingFetchRequest()
            }
            else {
                self.parseResult(records: array)
            }
        }

        database.add(operation)
    }
}
