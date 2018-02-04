//
//  ViewController.swift
//  SwiftyCloudKit
//
//  Created by Simen Gangstad on 02/04/2018.
//  Copyright (c) 2018 Simen Gangstad. All rights reserved.
//

import UIKit
import CloudKit
import SwiftyCloudKit

class ViewController: UIViewController, CloudKitFetcher {
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func handleCloudKitError(error: CKError) {
        
    }
    
    var database: CKDatabase = CKContainer.default().privateCloudDatabase
    var query: CKQuery?
    var existingRecords: [CKRecord] = []
    var interval: Int = 10
    var cursor: CKQueryCursor?
    var moreToFetch: Bool = false
    
    func terminatingFetchRequest() {
        
    }
    
    func parseResult(records: [CKRecord]) {
        
    }
    

}

