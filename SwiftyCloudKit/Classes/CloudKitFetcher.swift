import Foundation
import CloudKit

/**
 Lays the foundation for fetching records from iCloud.  The cloud kit fetcher fetches based on intervals set by the user. It will
 for example fetch records in an interval of 10. In a case where there is a total of 25 records, it'll fetch record 1-10, then 11-20,
 thereafter 21-25. It uses the CKQueryCursor to know which records it'll fetch during the next batch.
 */
@available (iOS 10.0, tvOS 10.0, OSX 10.12, *)
public protocol CloudKitFetcher: CloudKitHandler {
    
    /**
     The database the fetcher fetches from.
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

fileprivate struct AssociatedKeys {
    static fileprivate var fetchKey: UInt8 = 0
}

@available (iOS 10.0, tvOS 10.0, OSX 10.12, *)
public extension CloudKitFetcher {
    
    /**
     Makes it possible to control in further detail how multiple fetch request based on different parameters are executed.
     An example would be to fetch search results, where the cursor is set to nil, this state is set to more and another query is given based on the search terms.
     */
    private var fetchState: FetchState {
        get {
            return PropertyStoring<FetchState>.getAssociatedObject(forObject: self, key: &AssociatedKeys.fetchKey, defaultValue: .more)
        }
        set(newValue) {
            PropertyStoring<FetchState>.setAssociatedObject(forObject: self, key: &AssociatedKeys.fetchKey, value: newValue)
        }
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
            fetchState = .more
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
        
        operation.queryCompletionBlock = { [unowned self] (cursor, error) in
            if cursor != nil {
                self.cursor = cursor
            }
            else {
                if Reachability.isConnectedToNetwork() {
                    self.fetchState = .none
                }
            }
            
            var localRecords = LocalStorage.loadLocalRecords()
            print("Fetched \(localRecords.count) local records")
            // Local records
            if offlineSupport, !localRecords.isEmpty  {
                // We erase the local storage after storing the records in memory so that we don't duplicate the array every time.
                LocalStorage.eraseLocalRecords()

                let completion: ((CKRecord?, Error?) -> Void) = { (record, error) in
                    // Move uploaded record over to the record and remove it from the local records if the upload is successful.
                    if let record = record {
                        print("Local record uploaded successfully, deleting from local storage")
                        array.append(record)
                        localRecords.remove(at: localRecords.index(of: record)!)
                        _ = LocalStorage.delete(localRecord: record)
                    }
                }
                
                localRecords.forEach({ (record) in
                    print("Attempting to upload local record")
                    
                    self.upload(record: record, withCompletionHandler: { (uploadedRecord, error) in
                        guard error == nil else {
                            self.retryUploadAfter(error: error as? CKError, withRecord: record, andCompletionHandler: nil)
                            return
                        }
               
                        completion(uploadedRecord, error)
                    })
                })
                
                array.append(contentsOf: localRecords)
                // This will try to sort by the given sort descriptors of the query, but if the record was created offline it will not include
                // creation date and other parameters of the CKRecord as they seem to be assigned upon successfull upload.
                // A workaround is to add own parameters for e.g. date and sort by them, as creationDate is read only.
                if let sortDescriptors = self.query?.sortDescriptors {
                    array = array.sorted(sortDescriptors: sortDescriptors)
                }
            }
            
            completionHandler(array, error as? CKError)
        }
        
        database.add(operation)
    }
}
