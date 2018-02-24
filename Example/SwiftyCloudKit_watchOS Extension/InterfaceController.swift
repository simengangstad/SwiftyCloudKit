//
//  InterfaceController.swift
//  SwiftyCloudKit_watchOS Extension
//
//  Created by Simen Gangstad on 20.02.2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import WatchKit
import Foundation
import CloudKit
import SwiftyCloudKit
import WatchConnectivity

class InterfaceController: WKInterfaceController, WCSessionDelegate {

    let CloudKitTextField = "Text"
    
    @IBOutlet var table: WKInterfaceTable!
    
    var records = [CKRecord]()
    
    override func awake(withContext context: Any?) {
        super.awake(withContext: context)
        
        update(context)
    }
    
    func update(_ context: Any?) {
        guard let dictionary = context as? [String:CKRecord] else {
            return
        }
        
        records.removeAll()
        
        dictionary.forEach { (key, record) in
            records.insert(record, at: Int(key)!)
        }
        
        table.setNumberOfRows(records.count, withRowType: "cloudRow")
        for index in 0..<table.numberOfRows {
            guard let controller = table.rowController(at: index) as? CloudRowController else {
                continue
            }
            
            if let text = records[index].string(CloudKitTextField) {
                controller.label.setText(text)
            }
        }
    }
    
    override func willActivate() {
        super.willActivate()
        
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }
    
    override func didDeactivate() {
        // This method is called when watch view controller is no longer visible
        super.didDeactivate()
    }
    
    // MARK: WCSessionDelegate
    
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        
    }
    
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        update(applicationContext)
    }
}
