import CloudKit
import ObjectiveC
import UIKit
import Foundation

// MARK: Offine support

/**
 Indicates whether the library should deal with offline situations where it stores records locally temporarily, and uploads them when a connection
 is aquired.
 */
public var offlineSupport = true

/**
 Storage for the records which ought to be uploaded to iCloud, but failed in the process.
 CloudKitFetcher will try to upload these records in the next fetch call.
*/
internal var localStorageSavedRecords = LocalStorage(archiveName: "savedRecords")

/**
 Storage for the records which ought to be deleted in iCloud, but failed in the process.
 CloudKitFetcher will try to delete these records in the next fetch call.
*/
internal var localStorageDeletedRecords = LocalStorage(archiveName: "deletedRecords")

// MARK: Retrieving a copy of the data

/**
 Retrieves all the records stored in the given containers (both public and private databases). See [Providing User Access to CloudKit Data](https://developer.apple.com/documentation/cloudkit/providing_user_access_to_cloudkit_data/)
 
 - parameters:
    - containerRecordTypes: A dictionary of containers and record types, where the records of the given record types created by the user will be retrieved from the respective containers.
 
         **E.g.:**
 
         ```
         let containerRecordTypes: [CKContainer: [String]] = [
         defaultContainer: ["log", "verboseLog"],
         documents: ["textDocument", "spreadsheet"],
         settings: ["preference", "profile"]
         ]
         ```
 
 - returns: A dictionary of containers and records
 */
@available(iOS 10.0, *)
public func retrieveRecords(containerRecordTypes: [CKContainer: [String]]) -> [CKContainer: [CKRecord]] {
    let containers = Array(containerRecordTypes.keys)
    var recordDictionary = [CKContainer: [CKRecord]]()
    
    for container in containers {
        
        container.fetchUserRecordID { (userID, error) in
            guard error == nil else {
                return
            }
            
            if let userID = userID {
                for databaseScope in CKDatabase.Scope.cases {
                    recordDictionary[container]! += records(withRecordTypes: containerRecordTypes[container]!, fromDatabase: container.database(with: databaseScope), withUserID: userID)
                }
            }
        }
    }
    
    return recordDictionary
}

/**
 Returns all records with the given record types created by the current user from a given database.
 
 - parameters:
 - recordTypes: The record types to fetch
 - database: The database to fetch the records from
 */
private func records(withRecordTypes recordTypes: [String], fromDatabase database: CKDatabase, withUserID userID: CKRecord.ID) -> [CKRecord] {
    var allRecords = [CKRecord]()
    
    let reference = CKRecord.Reference(recordID: userID, action: .none)
    let predicate = NSPredicate(format: "creatorUserRecordID == %@", reference)
    
    database.fetchAllRecordZones { zones, error in
        guard let zones = zones, error == nil else {
            print(error!)
            return
        }
        
        for zone in zones {
            for recordType in recordTypes {
                let query = CKQuery(recordType: recordType, predicate: predicate)
                database.perform(query, inZoneWith: zone.zoneID) { records, error in
                    guard let records = records, error == nil else {
                        print("An error occurred fetching these records.")
                        return
                    }
                    
                    allRecords.append(contentsOf: records)
                }
            }
        }
    }
    
    return allRecords
}

@available(iOS 10.0, *)
extension CKDatabase.Scope {
    static var cases: [CKDatabase.Scope] {
        return [CKDatabase.Scope.public, CKDatabase.Scope.private, CKDatabase.Scope.shared]
    }
}

// MARK: Erasing data

/**
 Erases private user data stored in iCloud; Will remove everything in the private cloud databases in the containers passed to the function. See [Responding to Requests to Delete Data](https://developer.apple.com/documentation/cloudkit/responding_to_requests_to_delete_data/).
 
 - parameters:
     - containers: an array of the containers which should be erased.
     - completionHandler: gets fired after the erase
 */
public func erasePrivateData(inContainers containers: [CKContainer], completionHandler: @escaping (Error?) -> Void) {
	localStorageSavedRecords.eraseContentOfDirectory()
    localStorageDeletedRecords.eraseContentOfDirectory()
    
    for container in containers {
        
        print("Erasing private data from container \(container.containerIdentifier!)")
        
        container.privateCloudDatabase.fetchAllRecordZones { zones, error in
            guard let zones = zones, error == nil else {
                completionHandler(error)
                return
            }
            
            let zoneIDs = zones.map { $0.zoneID }
            let deletionOperation = CKModifyRecordZonesOperation(recordZonesToSave: nil, recordZoneIDsToDelete: zoneIDs)
            
            deletionOperation.modifyRecordZonesCompletionBlock = { _, deletedZones, error in
                guard error == nil else {
                    completionHandler(error)
                    return
                }
                
                print("Records successfully deleted in zones \(deletedZones!)")
            }
            
            container.privateCloudDatabase.add(deletionOperation)
        }
    }
    
    completionHandler(nil)
}

/**
 Erases public user data stored in iCloud; Will remove the records created by the user which are of the types passed to the function.
 
 - important: Make the record types queryable by user (createdBy) to make this function execute correctly.
 - parameters:
    - containerRecordTypes: A dictionary of containers and record types, where the records of the given record types created by the user will be deleted in the respective containers.
 
         **E.g.:**
 
         ```
         let containerRecordTypes: [CKContainer: [String]] = [
         defaultContainer: ["log", "verboseLog"],
         documents: ["textDocument", "spreadsheet"],
         settings: ["preference", "profile"]
         ]
         ```
    - completionHandler: gets fired after the erase
 
 */
public func eraseUserCreatedPublicData(containerRecordTypes: [CKContainer: [String]], completionHandler: @escaping (Error?) -> Void) {
    localStorageSavedRecords.eraseContentOfDirectory()
	localStorageDeletedRecords.eraseContentOfDirectory()
	
    
    for container in Array(containerRecordTypes.keys) {
        container.fetchUserRecordID { (userID, error) in
            
            guard error == nil else {
                completionHandler(error!)
                return
            }
            
            if let userID = userID {
                print("Erasing user created public data from container \(container.containerIdentifier!)")
                
                for recordType in containerRecordTypes[container]! {
                    removeAllInstances(inDatabase: container.publicCloudDatabase, ofRecordType: recordType, fromUserID: userID, completionHandler: completionHandler)
                }
            }
            
            completionHandler(nil)
        }
    }
}

/**
 Removes all instances of a record type in a specific database from a user ID
 
 - parameters:
 - database: The database to remove the records from
 - recordType: The record type to remove
 - userID: The userID to remove records from
 - completionHandler: gets fired after the erase
 */
private func removeAllInstances(inDatabase database: CKDatabase, ofRecordType recordType: String, fromUserID userID: CKRecord.ID, completionHandler: @escaping (Error?) -> Void) {
    let reference = CKRecord.Reference(recordID: userID, action: .none)
    let predicate = NSPredicate(format: "creatorUserRecordID == %@", reference)
    let query = CKQuery(recordType: recordType, predicate: predicate)
    
    database.fetchAllRecordZones { (zones, error) in
        guard let zones = zones, error == nil else {
            completionHandler(error)
            return
        }
        
        let zoneIDs = zones.map { $0.zoneID }
        for zoneID in zoneIDs {
            database.perform(query, inZoneWith: zoneID) { (records, error) in
                guard error == nil else {
                    completionHandler(error!)
                    return
                }
                
                if let records = records {
                    records.forEach{ (record) in
                        database.delete(withRecordID: record.recordID) { (recordID, error) in
                            guard error == nil else {
                                completionHandler(error!)
                                return
                            }
                        }
                    }
                }
            }
        }
    }
}


// MARK: Restriction

public enum Environment {
    case development, production
}

enum RestrictError: Error {
    case failure
}

/**
 Restricts the access to the private database of a given container. See [Changing Access Controls on User Data](https://developer.apple.com/documentation/cloudkit/changing_access_controls_on_user_data)
 
 - parameters:
    - container: Container containing the database.
    - apiToken: Reusable API token created in CloudKit Dashboard
    - environment: Development or production environment
    - completionHandler: Called when the restriction attempt is finished
 */
public func restrict(container: CKContainer, apiToken: String, webToken: String, environment: Environment, completionHandler: @escaping (Error?) -> Void) {
    let webToken = encodeToken(webToken)
    
    let identifier = container.containerIdentifier!
    var env: String!
    
    switch environment {
    case .development:
        env = "development"
    case .production:
        env = "production"
    }
    
    let baseURL = "https://api.apple-cloudkit.com/database/1/"
	let apiPath = "\(identifier)/\(String(describing: env))/private/users/restrict"
    let query = "?ckAPIToken=\(apiToken)&ckWebAuthToken=\(webToken)"
    
    let url = URL(string: "\(baseURL)\(apiPath)\(query)")!
    
    requestRestriction(url: url, completionHandler: completionHandler)
}

/**
 Lifts restrictions on the private database of a given container. See [Changing Access Controls on User Data](https://developer.apple.com/documentation/cloudkit/changing_access_controls_on_user_data)
 
 - parameters:
     - container: Container containing the database.
     - apiToken: Reusable API token created in CloudKit Dashboard
     - environment: Development or production environment
     - completionHandler: Called when the restrictions are lifted
 
 */
public func unrestrict(container: CKContainer, apiToken: String, webToken: String, environment: Environment, completionHandler: @escaping (Error?) -> Void) {
    let webToken = encodeToken(webToken)
    
    let identifier = container.containerIdentifier!
    var env: String!
    
    switch environment {
    case .development:
        env = "development"
    case .production:
        env = "production"
    }
    
    let baseURL = "https://api.apple-cloudkit.com/database/1/"
	let apiPath = "\(identifier)/\(String(describing: env))/private/users/unrestrict"
    let query = "?ckAPIToken=\(apiToken)&ckWebAuthToken=\(webToken)"
    
    let url = URL(string: "\(baseURL)\(apiPath)\(query)")!
    
    requestRestriction(url: url, completionHandler: completionHandler)
}

/**
 Retrieves web tokens for restricting or lifting restrictions of a given database.
 
 - parameters:
    - containerTokens: Dictionary of containers and their respective reusable APi tokens, created in CloudKit Dashboard
 
 - returns: Dictionary of the containers and their respective web tokens
 */
@available(iOS 9.2, *)
public func restrictTokens(forContainersWithAPITokens containerTokens: [CKContainer: String]) -> [CKContainer:String] {
    var tokens = [CKContainer:String]()
    
    for container in Array(containerTokens.keys) {
        guard let apiToken = containerTokens[container] else {
            continue
        }
        
        let fetchAuthorization = CKFetchWebAuthTokenOperation(apiToken: apiToken)
        
        fetchAuthorization.fetchWebAuthTokenCompletionBlock = { webToken, error in
            guard let webToken = webToken, error == nil else {
                return
            }
            tokens[container] = webToken
        }
        
        container.privateCloudDatabase.add(fetchAuthorization)
    }
    
    return tokens
}

/**
 Sends a restriction request or a request to lift restrictions for a given database.
 
 - parameters:
    - url: URL containing the request with the container identifier, reusable API tokens, web tokens and enviroment.
    - completionHandler: Fired after the request
 */
private func requestRestriction(url: URL, completionHandler: @escaping (Error?) -> Void) {
    let task = URLSession.shared.dataTask(with: url) { data, response, error in
        if let error = error {
            completionHandler(error)
            return
        }
        guard let httpResponse = response as? HTTPURLResponse,
            (200...299).contains(httpResponse.statusCode) else {
                completionHandler(RestrictError.failure)
                return
        }
        
        print("Restrict result", httpResponse)
        
        // Other than indicating success or failure, the `restrict` API doesn't return actionable data in its response.
        if data != nil {
            completionHandler(nil)
        } else {
            completionHandler(RestrictError.failure)
        }
    }
    task.resume()
}

private func encodeToken(_ token: String) -> String {
    return token.addingPercentEncoding(withAllowedCharacters: CharacterSet(charactersIn: "+/=").inverted) ?? token
}

// MARK: Record Types

public extension CKRecord {
    public func image(_ key: String) -> UIImage? {
        return (self[key] as? CKAsset)?.image
    }

    public func set(image: UIImage?, key: String)  {
        if let image = image {
            do {
                self[key] = try CKAsset(image: image)
            }
            catch let error {
                print("Error creating CKAsset from image: \(error)")
            }
        }
        else {
            self[key] = nil
        }
    }

    public func video(_ key: String) -> URL? {
        return (self[key] as? CKAsset)?.video(withFilename: "\(recordID.recordName)_\(key)")
    }

    public func set(video: URL?, key: String) {
        if let video = video {
            self[key] = CKAsset(fileURL: video)
        }
        else {
            self[key] = nil
        }
    }

    public func string(_ key: String) -> String? {
        return self[key] as? String
    }

    public func set(string: String?, key: String) {
        if let string = string {
            self[key] = string as CKRecordValue
        }
    }

    public func reference(_ key: String) -> CKRecord.Reference? {
        return self[key] as? CKRecord.Reference
    }

    public func set(reference: CKRecord.Reference?, key: String) {
        if let reference = reference {
            self[key] = reference as CKRecordValue
        }
    }

    public func data(_ key: String) -> Data? {
        return self[key] as? Data
    }

    public func set(data: Data?, key: String) {
        if let data = data {
            self[key] = data as CKRecordValue
        }
    }

    public func asset(_ key: String) -> CKAsset? {
        return self[key] as? CKAsset
    }

    public func set(asset: CKAsset?, key: String) {
        if let asset = asset {
            self[key] = asset as CKRecordValue
        }
    }

    public func int(_ key: String) -> Int? {
        return self[key] as? Int
    }

    public func set(int: Int?, key: String) {
        if let int = int {
            self[key] = int as CKRecordValue
        }
    }

    public func double(_ key: String) -> Double? {
        return self[key] as? Double
    }

    public func set(double: Double?, key: String) {
        if let double = double {
            self[key] = double as CKRecordValue
        }
    }

    public func location(_ key: String) -> CLLocation? {
        return self[key] as? CLLocation
    }

    public func set(location: CLLocation?, key: String) {
        if let location = location {
            self[key] = location as CKRecordValue
        }
    }

    public func date(_ key: String) -> Date? {
        return self[key] as? Date
    }

    public func set(date: Date?, key: String) {
        if let date = date {
            self[key] = date as CKRecordValue
        }
    }
    
    
    // MARK: Lists
    public func strings(_ key: String) -> [String]? {
        return self[key] as? [String]
    }
    
    public func set(strings: [String]?, key: String) {
        if let strings = strings {
            self[key] = strings as CKRecordValue
        }
    }
    
    public func references(_ key: String) -> [CKRecord.Reference]? {
        return self[key] as? [CKRecord.Reference]
    }
    
    public func set(references: [CKRecord.Reference]?, key: String) {
        if let references = references {
            self[key] = references as CKRecordValue
        }
    }
    
    public func data(_ key: String) -> [Data]? {
        return self[key] as? [Data]
    }
    
    public func set(data: [Data]?, key: String) {
        if let data = data {
            self[key] = data as CKRecordValue
        }
    }
    
    public func assets(_ key: String) -> [CKAsset]? {
        return self[key] as? [CKAsset]
    }
    
    public func set(assets: [CKAsset]?, key: String) {
        if let assets = assets {
            self[key] = assets as CKRecordValue
        }
    }
    
    public func ints(_ key: String) -> [Int]? {
        return self[key] as? [Int]
    }
    
    public func set(ints: [Int]?, key: String) {
        if let ints = ints {
            self[key] = ints as CKRecordValue
        }
    }
    
    public func doubles(_ key: String) -> [Double]? {
        return self[key] as? [Double]
    }
    
    public func set(doubles: [Double]?, key: String) {
        if let doubles = doubles {
            self[key] = doubles as CKRecordValue
        }
    }
    
    public func locations(_ key: String) -> [CLLocation]? {
        return self[key] as? [CLLocation]
    }
    
    public func set(locations: [CLLocation]?, key: String) {
        if let locations = locations {
            self[key] = locations as CKRecordValue
        }
    }
    
    public func dates(_ key: String) -> [Date]? {
        return self[key] as? [Date]
    }
    
    public func set(dates: [Date]?, key: String) {
        if let dates = dates {
            self[key] = dates as CKRecordValue
        }
    }
}

public enum ImageFileType {
    case JPG(compressionQuality: CGFloat)
    case PNG
    
    var fileExtension: String {
        switch self {
        case .JPG(_):
            return ".jpg"
        case .PNG:
            return ".png"
        }
    }
}

public enum ImageError: Error {
    case UnableToConvertImageToData
}

public extension CKAsset {
    public convenience init(image: UIImage, fileType: ImageFileType = .JPG(compressionQuality: 70)) throws {
        let url = try image.saveToTempLocationWithFileType(fileType: fileType)
        self.init(fileURL: url)
    }
    
    public var image: UIImage? {
        guard let data = NSData(contentsOf: fileURL), let image = UIImage(data: data as Data) else {
			print("Image file exists at path: \(FileManager.default.fileExists(atPath: fileURL.path))")
			return nil
		}
		
        return image
    }
    
    public func video(withFilename filename: String) -> URL? {
        return Data.retrieveOrCreateFile(withDataURL: fileURL, andFileName: "video_\(filename).mov", recreateIfFileExists: false)
    }
}

public extension Data {
    static func retrieveOrCreateFile(withDataURL fileURL: URL, andFileName fileName: String, recreateIfFileExists recreate: Bool) -> URL? {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let destinationPath = NSURL(fileURLWithPath: documentsPath).appendingPathComponent(fileName, isDirectory: false)
        
        if !recreate && FileManager.default.fileExists(atPath: destinationPath!.path) {
            return destinationPath
        }
        
        do {
            if FileManager.default.createFile(atPath: destinationPath!.path, contents: try Data(contentsOf: fileURL), attributes: nil) {
                return destinationPath!
            }
        }
        catch let error {
            print("Error creating file: \(error)")
            return nil
        }
        
        return nil
    }
}

public extension UIImage {
    fileprivate func saveToTempLocationWithFileType(fileType: ImageFileType) throws -> URL {
        let imageData: NSData?
        
        switch fileType {
        case .JPG(let quality):
            imageData = self.jpegData(compressionQuality: quality) as NSData?
        case .PNG:
            imageData = self.pngData() as NSData?
        }
        guard let data = imageData else {
            throw ImageError.UnableToConvertImageToData
        }
        
        let filename = ProcessInfo.processInfo.globallyUniqueString + fileType.fileExtension
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try data.write(to: url, options: .atomicWrite)
        
        return url
    }
}

/**
 Deletes the videos in the documents directory if there are any. This is to make sure that it isn't filled with videos as time goes on.
 */
public func deleteLocalVideos() {
    let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    guard let items = try? FileManager.default.contentsOfDirectory(atPath: documentsPath) else {
        return
    }
    
    print("Deleting videos in documents directory...")
    
    for item in items {
        if item.hasPrefix("video") {
            let completePath = documentsPath.appending("/\(item)")
            do {
                try FileManager.default.removeItem(atPath: completePath)
                print("Deleted: \(item)")
            }
            catch let error {
                print("Error removing file: \(completePath), error: \(error)")
            }
        }
    }
}

