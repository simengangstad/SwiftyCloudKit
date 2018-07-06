//
//  LocalStorageTest.swift
//  SwiftyCloudKit_Tests
//
//  Created by Simen Gangstad on 02/07/2018.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import XCTest
import SwiftyCloudKit
import Nimble
import CloudKit

class LocalStorageTest: XCTestCase {

	let record = CKRecord(recordType: "Record",
						  recordID: CKRecord.ID(recordName: UUID().uuidString, zoneID: CKRecordZone.ID(zoneName: "RecordZone", ownerName: CKCurrentUserDefaultName)))
	let storage = LocalStorage(archiveName: "localStorageTest")
	
    override func setUp() {
		record.set(string: "Hello World", key: "text")
		record.set(date: Date(), key: "date")
		record.set(image: UIImage(named: "fall"), key: "image")
		
		let url = Bundle.main.url(forResource: "video", withExtension: "mov")
		record.set(video: url, key: "video")
		
		storage.createDirectory()
    }

    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
	
	func testSave() {
		storage.createDirectory()
		storage.eraseContentOfDirectory()
		storage.save(record: record)
		print(try! FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))
		expect(FileManager.default.fileExists(atPath: self.storage.archiveURL.path)).to(equal(true))
		expect(try! FileManager.default.contentsOfDirectory(at: self.storage.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).count).to(equal(3))
	}

	func testEraseContent() {
		storage.createDirectory()
		storage.save(record: record)
		storage.eraseContentOfDirectory()
		print(try! FileManager.default.contentsOfDirectory(at: storage.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles))
		expect(try FileManager.default.contentsOfDirectory(at: self.storage.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).count).to(equal(0))
	}
	
	func testDelete() {
		storage.createDirectory()
		storage.eraseContentOfDirectory()
		storage.save(record: record)
		storage.delete(record: record)
		let records = self.storage.load()
		print(records)
		expect(records.count).to(equal(0))
	}

    func testPerformance() {
        self.measure {
        }
    }

}
