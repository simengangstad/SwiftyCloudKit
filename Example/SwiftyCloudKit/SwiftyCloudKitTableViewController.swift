//
//  SwiftyCloudKitTableViewController.swift
//  
//
//  Created by Simen Gangstad on 06.02.2018.
//

import UIKit
import CloudKit
import SwiftyCloudKit

class SwiftyCloudKitTableViewController: UITableViewController, CloudKitFetcher, CloudKitHandler {

    // MARK: Model
    
    let CloudKitTextField = "Text"
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
        
        fetch()
        startActivityIndicator()
    }
    
    // MARK: Cloud Kit Fetcher
    
    var database: CKDatabase = CKContainer.default().privateCloudDatabase
    
    var query: CKQuery? {
        let query = CKQuery(recordType: CloudKitRecordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
        query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return query
    }
    
    var existingRecords: [CKRecord] { return records }
    
    var interval: Int = 10
    
    var cursor: CKQueryCursor?
    
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
    func handleCloudKitError(error: CKError) {
        
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
