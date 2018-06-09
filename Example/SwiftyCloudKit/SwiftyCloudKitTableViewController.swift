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
        let refreshControl = UIRefreshControl()
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        tableView.refreshControl = refreshControl
    }
    
    var countOfLocalRecords: Int!
    
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // We start fetching, but don't want to fetch every time the view appears on screen, therefore we check if the records is empty or not
        if records.isEmpty {
            refresh()
        }
        
        subscribe(nil)
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        unsubscribe(nil)
    }
    
    // Refresh table view
    
    private var removeRecords = true
    
    @objc private func refresh() {
        cursor = nil
        startActivityIndicator()
        
        removeRecords = true
        fetch(withCompletionHandler: parseResult)
    }
    
    // MARK: Cloud kit fetcher
	
	// Specify the database, could also be the publicCloudDatabase if one were to share data between multiple users, but in this case we fetch from our private iCloud database
	var database: CKDatabase = CKContainer.default().privateCloudDatabase
	
	var query: CKQuery? {
		// Specify that we want all the records stored in the database using the "TRUEPREDICATE" predicate, and that we'll sort them by when they were created
		let query = CKQuery(recordType: CloudKitRecordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
		query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
		return query
	}
	
	// The amount of records we'll fetch for each request
	var interval: Int = 5
	
	// The cursor is an object which helps us keep track of which records we've fetched, and which records we are to fetch during the next batch. Can be set to nil to start fetching from the start.
	var cursor: CKQueryOperation.Cursor?
	
	var zoneID: CKRecordZone.ID = CKRecordZone.default().zoneID
	
	var desiredKeys: [String]? = nil
	
    private func parseResult(fetchedRecords: [CKRecord]?, error: CKError?) {
        DispatchQueue.main.async { [unowned self] in
            if let error = error {
                print(error.localizedDescription)
            }
            
            print("Retrieved records, reloading table view...")
            
            if self.removeRecords {
                self.records.removeAll()
            }
            
            if let fetchedRecords = fetchedRecords {
                self.records.append(contentsOf: fetchedRecords)
            }
            
            self.stopActivityIndicator()
            self.tableView.refreshControl?.endRefreshing()
            
            if self.records.count > self.interval {
                self.tableView.reloadData()
            }
            else {
                self.tableView.beginUpdates()
                self.tableView.reloadSections(IndexSet(integer: 0), with: .top)
                self.tableView.endUpdates()
            }
            
            self.removeRecords = false
        }
    }
	
    // MARK: Cloud kit subscriber
    
    // Specify that we want to listen to all updates concering the CloudKitRecordType
    var subscription: CKQuerySubscription {
        let subscription = CKQuerySubscription(recordType: CloudKitRecordType,
                                               predicate: NSPredicate(format: "TRUEPREDICATE"),
                                               subscriptionID: "All records creation, deletions and updates",
                                               options: [.firesOnRecordCreation, .firesOnRecordDeletion, .firesOnRecordUpdate])
        
		let notificationInfo = CKSubscription.NotificationInfo()
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
                            print(error.localizedDescription)
                        }
                        else {
                            if let record = record {
                                DispatchQueue.main.async {
                                    self.records.insert(record, at: 0)
                                    self.tableView.beginUpdates()
									self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: UITableView.RowAnimation.top)
									self.tableView.endUpdates()
                                    self.stopActivityIndicator()
                                }
                            }
                        }
                    }
                
                case .recordDeleted:
                    DispatchQueue.main.async {
                        let index = self.records.index(where: { $0.recordID == recordID })
                        self.records.remove(at: index!)
                        self.tableView.beginUpdates()
						self.tableView.deleteRows(at: [IndexPath(row: index!, section: 0)], with: UITableView.RowAnimation.bottom)
						self.tableView.endUpdates()
                    }
                    
                case .recordUpdated:
                    startActivityIndicator()
                    database.fetch(withRecordID: recordID) { (record, error) in
                        if let error = error as? CKError {
                            print(error.localizedDescription)
                        }
                        else {
                            if let record = record {
                                DispatchQueue.main.async {
                                    let index = self.records.index(where: { $0.recordID == record.recordID })!
                                    self.records[index] = record
                                    self.tableView.beginUpdates()
                                    self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .automatic)
                                    self.tableView.endUpdates()
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
        
        upload(record: record) { [unowned self] (addedRecord, error) in
            DispatchQueue.main.async {
                
                if let error = error as? CKError {
                    print(error.localizedDescription)
                    self.stopActivityIndicator()
                }

                if let addedRecord = addedRecord {
                    print("Record saved")
                    self.records.insert(addedRecord, at: 0)
                    self.tableView.beginUpdates()
                    self.tableView.insertRows(at: [IndexPath(row: 0, section: 0)], with: .top)
                    self.tableView.endUpdates()
                }
            }
        }
    }
    
    // MARK: Erasing items and user data
    
    @IBAction func eraseData(_ sender: UIBarButtonItem) {
        erasePrivateData(inContainers: [CKContainer.default()]) { (error) in
            guard error == nil else {
                print(error!)
                return
            }
            
            self.records.removeAll()
            self.tableView.reloadData()
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
	override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
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
