//
//  SwiftyCloudKitTableViewController.swift
//  
//
//  Created by Simen Gangstad on 06.02.2018.
//

import UIKit
import CloudKit
import SwiftyCloudKit

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
        
        // We start fetching
        fetch()
        startActivityIndicator()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        subscribeToUpdates()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        unsubscribeToUpdates()
    }
    
    // MARK: Cloud Kit Fetcher
    
    // Specify the database, could also be the publicCloudDatabase if one were to share data between multiple users
    var database: CKDatabase = CKContainer.default().privateCloudDatabase
    
    var query: CKQuery? {
        // Specify that we want all records using the TRUEPREDICATE predicate, and that we'll sort them by when they were created
        let query = CKQuery(recordType: CloudKitRecordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return query
    }
    
    var existingRecords: [CKRecord] { return records }
    
    var interval: Int = 10
    
    var cursor: CKQueryCursor?
    
    // Append the fetched records to the table view
    func parseResult(records: [CKRecord]) {
        DispatchQueue.main.async { [unowned self] in
            print("Retrieved records, reloading table view...")
            self.records = records
            
            if self.records.count > self.interval {
                self.tableView.reloadData()
            }
            else {
                self.tableView.reloadSections(IndexSet(integer: 0), with: .top)
            }
            
            self.stopActivityIndicator()
        }
    }
    
    func terminatingFetchRequest() {
        DispatchQueue.main.async {
            self.stopActivityIndicator()
        }
    }
    
    // MARK: Cloud kit subscriber
    
    // Specify that we want to listen to all updates concering the CloudKitRecordType
    var subscription: CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: CloudKitRecordType,
                                               predicate: NSPredicate(format: "TRUEPREDICATE"),
                                               subscriptionID: "All records creation, deletions and updates",
                                               options: [.firesOnRecordCreation, .firesOnRecordDeletion, .firesOnRecordUpdate])
        
        let notificationInfo = CKNotificationInfo()
        notificationInfo.alertLocalizationKey = "New Records"
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
    
    // MARK: Adding items
    
    @IBAction func addItem(_ sender: UIBarButtonItem) {
        let record = CKRecord(recordType: CloudKitRecordType)
        record.set(string: "\(records.count + 1)", key: CloudKitTextField)
        startActivityIndicator()
        upload(record: record) { [unowned self] (uploadedRecord) in
            DispatchQueue.main.async {
                guard let uploadedRecord = uploadedRecord else {
                    self.displayDestructiveAlertMessage(withTitle: "iCloud error", andMessage: "There was an error uploading to iCloud")
                    return
                }
                
                self.stopActivityIndicator()
                print("Record uploaded")
                self.records.insert(uploadedRecord, at: 0)
                self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
            }
        }
    }
    
    // MARK: Activity indicator
    let activityIndicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)

    func startActivityIndicator() {
        if navigationItem.leftBarButtonItem == nil {
            navigationItem.leftBarButtonItem = UIBarButtonItem(customView: activityIndicator)
        }
        
        activityIndicator.startAnimating()
    }
    
    func stopActivityIndicator() {
        activityIndicator.stopAnimating()
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
            delete(record: records[indexPath.row], withCompletionHandler: { [unowned self] (deletedRecordID) in
                DispatchQueue.main.async {
                    guard deletedRecordID != nil else {
                        self.displayDestructiveAlertMessage(withTitle: "iCloud error", andMessage: "There was an error deleting the record in iCloud")
                        return
                    }
                    
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
