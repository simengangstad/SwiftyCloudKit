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
     The ID of the zone to fetch from.
     */
    var zoneID: CKRecordZone.ID { get }
	
	/**
	The keys to fetch. Set to nil if the fetcher should fetch all the keys.
	*/
	var desiredKeys: [String]? { get }
    
    /**
     The cursor which keeps control over which records that are to be fetched during the next batch. Is set to nil when all the records are fetched.
     */
    var cursor: CKQueryOperation.Cursor? { get set }
    
    /**
     Fetches the records stored in iCloud based on the parameters given to the cloud kit fetcher. This method will also upload any local records and
	 try to delete any records which ought to be deleted in iCloud, but failed in the process.
     
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
        operation.zoneID = zoneID
        operation.qualityOfService = .userInitiated
		operation.desiredKeys = desiredKeys
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
            
            var savedRecords = localStorageSavedRecords.load()
			var deletedRecords = localStorageDeletedRecords.load()

			print("Fetched \(savedRecords.count) local records that ought to be uploaded to iCloud")
			print("Fetched \(deletedRecords.count) local records that ought to be deleted in iCloud")

			array = array.filter { (record) in !deletedRecords.contains(where: { $0.recordID == record.recordID }) }
			
            // Local records
            if offlineSupport && (!savedRecords.isEmpty || !deletedRecords.isEmpty )  {
				if !savedRecords.isEmpty && Reachability.isConnectedToNetwork() {
					let savedCompletion: (([CKRecord]?) -> Void) = { (records) in
						// Move uploaded record over to the record and remove it from the local records if the upload is successful.
						if let records = records {
							print("Local records uploaded successfully, deleting from local storage")
							
							for record in records {
								if let index = savedRecords.firstIndex(where: { record.recordID == $0.recordID }) {
									savedRecords.remove(at: index)
								}
								
								localStorageSavedRecords.delete(record: record)
							}
						}
					}
					
					self.performModifyOperation(recordsToSave: savedRecords, recordIDsToDelete: nil) { (uploadedRecords, _, error) in
						guard error == nil else {
							return
						}
						
						savedCompletion(uploadedRecords)
					}
				}
				
				if !deletedRecords.isEmpty && Reachability.isConnectedToNetwork() {
					let deleteCompletion: (([CKRecord.ID]?) -> Void) = { (deletedRecordIDs) in
						if deletedRecordIDs != nil {
							print("Local record deletion success, deleting from local storage")
							
							for deletedRecordID in deletedRecordIDs! {
								if let index = deletedRecords.firstIndex(where: { deletedRecordID == $0.recordID }) {
									localStorageDeletedRecords.delete(record: deletedRecords[index])
								}
							}
						}
					}
					
					self.performModifyOperation(recordsToSave: nil, recordIDsToDelete: deletedRecords.map({ $0.recordID  })) { (_, deletedRecordIDs, error) in
						guard error == nil else {
							return
						}
						
						deleteCompletion(deletedRecordIDs)
					}
				}
                
                array.append(contentsOf: savedRecords)
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
	
	private func performModifyOperation(recordsToSave: [CKRecord]?, recordIDsToDelete: [CKRecord.ID]?, completionHandler: @escaping (([CKRecord]?, [CKRecord.ID]?, Error?) -> Void)) {
		let modifyOperation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: recordIDsToDelete)
		modifyOperation.savePolicy = .allKeys
		modifyOperation.qualityOfService = .userInitiated
		modifyOperation.modifyRecordsCompletionBlock = { (uploadedRecords, deletedRecords, error) in
			completionHandler(uploadedRecords, deletedRecords, error)
		}
		
		database.add(modifyOperation)
	}
}
