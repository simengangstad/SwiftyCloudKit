import CloudKit

/**
 Lays the foundation for fetching records from iCloud. The cloud kit fetcher fetches based on intervals set by the user. It will for
 example fetch records in an interval of 10. In a case where there is a total of 25 records, it'll fetch record 1-10, then 11-20, thereafter
 21-25. It uses the CKQueryCursor to know which records it'll fetch during the next batch.
 */
public protocol CloudKitFetcher: AnyObject, PropertyStoring {
    
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
     
     - parameters
        - completionHandler: encapsulates the records fetched and errors, if any.
     */
    func fetch(withCompletionHandler completionHandler: @escaping ([CKRecord]?, CKError?) -> Void)
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
    
    public func fetch(withCompletionHandler completionHandler: @escaping ([CKRecord]?, CKError?) -> Void) {
        var operation: CKQueryOperation!
        var array = [CKRecord]()

        if cursor == nil {
            guard let query = query else {
                completionHandler(nil, CKError(_nsError: NSError(domain: "ck fetch", code: CKError.serviceUnavailable.rawValue, userInfo: nil)))
                return
            }
        
            operation = CKQueryOperation(query: query)
        }
        else {
            operation = CKQueryOperation(cursor: cursor!)
        }

        operation.resultsLimit = interval
        operation.qualityOfService = .userInitiated
        operation.recordFetchedBlock = { [unowned self] in
            if self.fetchState == .more {
                array.append($0)
            }
        }
        
        // TODO: Completion handler is never fired when the device isn't connected to the internet
        operation.queryCompletionBlock = { [unowned self] (cursor, error) in
            if cursor != nil {
                self.cursor = cursor
            }
            else {
                self.fetchState = .none
            }
            
            completionHandler(array, error as? CKError)
        }

        database.add(operation)
    }
}
