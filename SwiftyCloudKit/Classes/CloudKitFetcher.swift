import CloudKit

/**
 Lays the foundation for fetching records from iCloud. The cloud kit fetcher fetches based on intervals set by the user. It will for
 example fetch records in an interval of 10. In a case where there is a total of 25 records, it'll fetch record 1-10, then 11-20, thereafter
 21-25. It uses the CKQueryCursor to know which records it'll fetch during the next batch.
 */
public protocol CloudKitFetcher: CloudKitErrorHandler, PropertyStoring {
    
    /**
     The database the fetcher fetches records from, can either be the private or the public database.
    */
    var database: CKDatabase { get }
    
    /**
     The query the fetcher will fetch by. See [NSPredicate](https://developer.apple.com/documentation/foundation/nspredicate)
     and [NSSortDescriptor](https://developer.apple.com/documentation/foundation/nssortdescriptor) for more information on how the
     query can be set up.
     */
    var query: CKQuery? { get }
    
    /**
     The amount of records fetched per batch.
    */
    var interval: Int { get }
    
    /**
     The cursor which keeps control over which records that are to be fetched during the next batch. Is set to nil when all the records are fetched.
     */
    var cursor: CKQueryCursor? { get set }

    /**
     Fetches the records stored in iCloud based on the parameters given to the cloud kit fetcher.
     */
    func fetch()
    
    /**
     Parses the fetched records. This is where the cloud kit fetcher returns the records it has fetched.
     
     - parameters:
        - records: The records fetched in the fetch() function.
     
     - important:
    This function will get called from a global asynchronous thread. Switch to the main thread before you make changes to the UI, e.g. reloading the data in a table view.
    */
    func parseResult(records: [CKRecord])
    
    /**
     Is called when an error occurred during the fetch operation and the fetch request had to be terminated. Use this function to stop loading animations
     and similar things.
     
     - important:
    This function will get called from a global asynchronous thread.
    */
    func terminatingFetchRequest()
}

/**
 An enum which defines if the cloud kit fetcher has more to fetch or not. Is used to control the fetch operation in further detail.
 */
public enum FetchState {
    case more, none
}

private var fetchKey: UInt8 = 0

public extension CloudKitFetcher {
    
    typealias T = FetchState

    /**
     Makes it possible to control in further detail how multiple fetch request based on different parameters are executed.
     An example would be to fetch search results, where the cursor is set to nil, this state is set to more and another query is given based on the search terms.
    */
    public var fetchState: FetchState {
        get { return getAssociatedObject(&fetchKey, defaultValue: .more)}
        set { return setAssociatedObject(&fetchKey, value: newValue)}
    }
    
    public func fetch() {
        var operation: CKQueryOperation!
        var array = [CKRecord]()

        if cursor == nil {
            guard let query = query else {
                handle(cloudKitError: CKError(_nsError: NSError(domain: "ck fetch", code: CKError.serviceUnavailable.rawValue, userInfo: nil)))
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
                self.handle(cloudKitError: error)
                self.terminatingFetchRequest()
            }
            else {
                self.parseResult(records: array)
            }
        }

        database.add(operation)
    }
}
