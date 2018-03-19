//
//  SwiftyCloudKitTableViewController.swift
//  
//
//  Created by Simen Gangstad on 06.02.2018.
//
import UIKit
import CloudKit
import SwiftyCloudKit
#if !os(tvOS)
import WatchConnectivity
#endif

class SwiftyCloudKitTableViewController: UITableViewController, CloudKitFetcher, CloudKitHandler, CloudKitSubscriber {
    
    // MARK: Model
    
    // The text field in our record
    let CloudKitTextField = "Text"
    
    // The key to our record
    let CloudKitRecordType = "Record"
    var records = [CKRecord]()
    
    
    // MARK: View cycle
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        activityIndicator.hidesWhenStopped = true
        
        #if !os(tvOS)
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
        #endif
    }
    
    var countOfLocalRecords: Int!
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // We start fetching. Don't want to fetch every time the view appears on screen.
        if records.isEmpty {
            fetch(withCompletionHandler: { (fetchedRecords, error) in
                DispatchQueue.main.async { [unowned self] in
                    
                    if let localRecords = self.loadLocalRecords() {
                        self.localRecords = localRecords
                        self.countOfLocalRecords = self.localRecords.count
                    }
                    
                    if let error = error {
                        print(error.localizedDescription)
                        self.stopActivityIndicator()
                    }
                    else {
                        print("Retrieved records, reloading table view...")
                        
                        if let fetchedRecords = fetchedRecords {
                            self.records.append(contentsOf: fetchedRecords)
                            
                            #if !os(tvOS)
                                self.update(recordsForWatch: self.records)
                            #endif
                        }
                        
                        // We got connection to iCloud, upload the local records
                        
                        if !self.localRecords.isEmpty {
                            let completionHandler: ((CKRecord?, CKError?) -> Void) = { (localRecordUploaded, error) in
                                if let recordUploaded = localRecordUploaded {
                                    print("Successfully uploaded record \(self.countOfLocalRecords - self.localRecords.count + 1)/\(self.countOfLocalRecords)")
                                    self.localRecords.remove(at: self.localRecords.index(of: recordUploaded)!)
                                    if !self.saveLocalRecords() {
                                        print("Error updating local records")
                                    }
                                }
                            }
                            
                            print("Uploading local records (\(self.localRecords.count)")
                            
                            self.localRecords.forEach({ (record) in
                                self.upload(record: record, withCompletionHandler: { (uploadedRecord, error) in
                                    guard error == nil else {
                                        self.retryUploadAfter(error: error, withRecord: record, andCompletionHandler: completionHandler)
                                        return
                                    }
                                    
                                    completionHandler(uploadedRecord, error)
                                })
                            })
                        }
    
                        self.stopActivityIndicator()
                    }
                    
                    self.records.append(contentsOf: self.localRecords)
                    // Sort records
                    
                    if self.records.count > self.interval {
                        self.tableView.reloadData()
                    }
                    else {
                        self.tableView.reloadSections(IndexSet(integer: 0), with: .top)
                    }
                }
            })
            
            startActivityIndicator()
        }
        
        subscribe(nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        unsubscribe(nil)
    }
    
    // MARK: Cloud Kit Fetcher
    
    // Specify the database, could also be the publicCloudDatabase if one were to share data between multiple users, but in this case we fetch from our private iCloud database
    var database: CKDatabase = CKContainer.default().privateCloudDatabase
    
    var query: CKQuery? {
        // Specify that we want all the records stored in the database using the "TRUEPREDICATE" predicate, and that we'll sort them by when they were created
        let query = CKQuery(recordType: CloudKitRecordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return query
    }
    
    // The amount of records we'll fetch for each request
    var interval: Int = 10
    
    // The cursor is an object which helps us keep track of which records we've fetched, and which records we are to fetch during the next batch. Can be set to nil to start fetching from the start.
    var cursor: CKQueryCursor?
    
    // MARK: Cloud kit subscriber
    
    // Specify that we want to listen to all updates concering the CloudKitRecordType
    var subscription: CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: CloudKitRecordType,
                                               predicate: NSPredicate(format: "TRUEPREDICATE"),
                                               subscriptionID: "All records creation, deletions and updates",
                                               options: [.firesOnRecordCreation, .firesOnRecordDeletion, .firesOnRecordUpdate])
        
        let notificationInfo = CKNotificationInfo()
        #if os(iOS) || os(macOS)
            notificationInfo.alertLocalizationKey = "New Records"
        #endif
        notificationInfo.shouldBadge = true
        subscription.notificationInfo = notificationInfo
        
        return subscription
    }
    
    // Deal with the different types of subscription notifications
    func handleSubscriptionNotification(ckqn: CKQueryNotification) {
        if ckqn.subscriptionID == subscription.subscriptionID {
            if let recordID = ckqn.recordID {
                switch ckqn.queryNotificationReason {
                    
                case .recordCreated:
                    startActivityIndicator()
                    database.fetch(withRecordID: recordID) { (record, error) in
                        
                        if let error = error as? CKError {
                            self.handle(cloudKitError: error)
                        }
                        else {
                            if let record = record {
                                DispatchQueue.main.async {
                                    self.records.insert(record, at: 0)
                                    #if !os(tvOS)
                                    self.update(recordsForWatch: self.records)
                                    #endif
                                    self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: UITableViewRowAnimation.top)
                                    self.stopActivityIndicator()
                                }
                            }
                        }
                    }
                
                case .recordDeleted:
                    DispatchQueue.main.async {
                        let index = self.records.index(where: { $0.recordID == recordID })
                        self.records.remove(at: index!)
                        #if !os(tvOS)
                        self.update(recordsForWatch: self.records)
                        #endif
                        self.tableView.deleteRows(at: [IndexPath(row: index!, section: 0)], with: UITableViewRowAnimation.bottom)
                    }
                    
                case .recordUpdated:
                    startActivityIndicator()
                    database.fetch(withRecordID: recordID) { (record, error) in
                        if let error = error as? CKError {
                            self.handle(cloudKitError: error)
                        }
                        else {
                            if let record = record {
                                DispatchQueue.main.async {
                                    let index = self.records.index(where: { $0.recordID == record.recordID })!
                                    self.records[index] = record
                                    #if !os(tvOS)
                                    self.update(recordsForWatch: self.records)
                                    #endif
                                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
                                    self.stopActivityIndicator()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    
    // MARK: Local records
    
    static let DocumentsDirectory = FileManager().urls(for: .documentDirectory, in: .userDomainMask).first!
    static let ArchiveURL = DocumentsDirectory.appendingPathComponent("records")

    func saveLocalRecords() -> Bool {
        return NSKeyedArchiver.archiveRootObject(localRecords, toFile: SwiftyCloudKitTableViewController.ArchiveURL.path)
    }
    
    func loadLocalRecords() -> [CKRecord]? {
        return NSKeyedUnarchiver.unarchiveObject(withFile: SwiftyCloudKitTableViewController.ArchiveURL.path) as? [CKRecord]
    }
    
    var localRecords = [CKRecord]()
    
    // MARK: Adding items
    
    @IBAction func addItem(_ sender: UIBarButtonItem) {
        let record = CKRecord(recordType: CloudKitRecordType)
        record.set(string: "\(records.count + 1)", key: CloudKitTextField)
        startActivityIndicator()
        
        upload(record: record) { [unowned self] (uploadedRecord, error) in
            DispatchQueue.main.async {
                if let error = error {
                    
                    switch error.code {
                    case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
                        // Saving locally
                        self.localRecords.insert(record, at: 0)
                        self.records.insert(record, at: 0)
                        self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
                        
                        if self.saveLocalRecords() {
                            print("Managed to save record locally")
                        }
                        else {
                            print("Failed to save locally")
                        }
                    default:
                        print(error.localizedDescription)
                    }
                    
                    self.stopActivityIndicator()
                }
                else {
                    
                    if let uploadedRecord = uploadedRecord {
                        self.stopActivityIndicator()
                        print("Record uploaded")
                        self.records.insert(uploadedRecord, at: 0)
                        #if !os(tvOS)
                            self.update(recordsForWatch: self.records)
                        #endif
                        self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
                    }
                }
            }
        }
    }
    
    // MARK: Activity indicator
    #if os(iOS)
        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
    #elseif os(tvOS)
        let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .white)
    #endif

    func startActivityIndicator() {
        #if os(iOS) || os(tvOS)
            if navigationItem.leftBarButtonItem == nil {
                navigationItem.leftBarButtonItem = UIBarButtonItem(customView: activityIndicator)
            }
    
            activityIndicator.startAnimating()
        #endif
    }
    
    func stopActivityIndicator() {
        #if os(iOS) || os(tvOS)
            activityIndicator.stopAnimating()
        #endif
    }
    
    // MARK: Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return records.count
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cellIdentifier", for: indexPath)
        // Notice how we access our field, with a call to string passing our constant for the text field type
        cell.textLabel?.text = records[indexPath.row].string(CloudKitTextField)
        return cell
    }

    
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            
            delete(record: records[indexPath.row], withCompletionHandler: { [unowned self] (recordID, error) in
                DispatchQueue.main.async {
                    print("Record deleted")
                    self.records.remove(at: indexPath.row)
                    tableView.deleteRows(at: [indexPath], with: .fade)
                }
            })
        }
    }
    
    func displayDestructiveAlertMessage(withTitle title: String, andMessage message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "Cancel", style: .destructive, handler: nil))
        present(alertController, animated: true, completion: nil)
    }
}

// MARK: Cloud Kit Error Handler
extension SwiftyCloudKitTableViewController {
    func handle(cloudKitError error: CKError) {
        
        var errorMessage: String!
        
        switch error.code {
            
        case .networkUnavailable:
            errorMessage = "Swifty cloud kit requires a network connection"
            break
            
        case .networkFailure:
            errorMessage = "There was an error establishing a successful connection to the network"
            break
            
        case .serviceUnavailable:
            errorMessage = "Could not establish a connection with iCloud's service, try agin later"
            break
            
        case .requestRateLimited:
            errorMessage = "Request rates for iCloud services are temporarily limited, try again later"
            break
            
        case .notAuthenticated:
            errorMessage = "Swifty cloud kit relies its services on Apple's servers through iCloud, therefore an iCloud login is required. Log on to iCloud."
            break
            
        case .unknownItem:
            errorMessage = "Entry does not exist anymore"
            break
            
        case .quotaExceeded:
            errorMessage = "Cannot save as this entry would exceed the device quota"
            break
            
        default:
            errorMessage = "Cloud kit request failed with error code \(error.errorCode)"
            break
            
        }

        displayDestructiveAlertMessage(withTitle: "iCloud", andMessage: "\(errorMessage!) - \(error.localizedDescription)")
    }
}

#if !os(tvOS)
extension SwiftyCloudKitTableViewController: WCSessionDelegate {
    // MARK: WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        /*switch activationState {
         case .notActivated:
         
         case .inactive:
         
         case: .active
         
         }*/
    }
    
    func sessionDidBecomeInactive(_ session: WCSession) {
        
    }
    
    func sessionDidDeactivate(_ session: WCSession) {
        
    }
    
    // MARK: Watch kit
    
    func update(recordsForWatch records: [CKRecord]) {
        if WCSession.default.isReachable {
            var context = [String:CKRecord]()
            for (index, record) in records.enumerated() {
                context[index.description] = record
            }
            
            do {
                try WCSession.default.updateApplicationContext(context)
            }
            catch let error {
                print(error)
            }
        }
    }
}
#endif
