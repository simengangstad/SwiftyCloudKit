# SwiftyCloudKit

[![CI Status](http://img.shields.io/travis/simengangstad/SwiftyCloudKit.svg?style=flat)](https://travis-ci.org/simengangstad/SwiftyCloudKit) [![Version](https://img.shields.io/cocoapods/v/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![License](https://img.shields.io/cocoapods/l/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![Platform](https://img.shields.io/cocoapods/p/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit)

SwiftyCloudKit is a thin layer above Cloud Kit which makes it easy to implement cloud support into an iOS app. The library is structured into modules which can be used independently or toghether, all after need.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory first. It is strongly recommended to run through the tutorial with the example project.

## Requirements

- Swift 4.0
- iOS 10.0 or newer

## Installation

SwiftyCloudKit is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SwiftyCloudKit'
```

## Use

There are four submodules – or protocols – of SwiftyCloudKit: CloudKitFetcher, CloudKitHandler, CloudKitSubscriber and CloudKitErrorHandler.

### CloudKitErrorHandler

All the following modules will call the error handler when an error occurs. Therefore it is required  to implement this protocol as all of the other protocols inherits from it. It is done with the following function:

```
func handle(cloudKitError error: CKError) {
    // Handle errors
}
```

### CloudKitFetcher

The cloud kit fetcher fetches records from iCloud. You specify a database, a query, a reference to your existing records and an fetch interval (in terms of records) and you are more or less good to go. You also have to implement the `parseResult(records: [CKRecord])`  function, which returns the records fetched, and the `terminatingFetchRequest()` function, which allows you to know when a fetch request was terminated because of some error. This example is built with a UITableViewController (taken from the example project).

We define a simple model:

```
// The key to our record
let CloudKitRecordType = "Record"
// Model
var records = [CKRecord]()
```

And conform to the CloudKitFetcher protocol:

```
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

// Append the fetched records to our model and reload table view
func parseResult(records: [CKRecord]) {
    DispatchQueue.main.async { [unowned self] in
        print("Retrieved records, reloading table view...")
        self.records.append(contentsOf: records)

        if self.records.count > self.interval {
            self.tableView.reloadData()
        }
        else {
            self.tableView.reloadSections(IndexSet(integer: 0), with: .top)
        }
        self.stopActivityIndicator()
    }
}

// If there occured an error we stop e.g. activity indicators
func terminatingFetchRequest() {
    DispatchQueue.main.async {
        self.stopActivityIndicator()
    }
}
```

Setup a record type in the cloud kit dashboard and you should be up and running.

##### Accessing values

To access values from records you specify a field key, e.g. `let CloudKitTextField = "Text"` and acess it with the `string(_ key: String) -> String?` function, as seen in the table view data source in the example project:

```
override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cellIdentifier", for: indexPath)
    // Notice how we access our field, with a call to string passing our constant for the text field type
    cell.textLabel?.text = records[indexPath.row].string(CloudKitTextField)
    return cell
}
```

There exist such helper functions for every type exept the list types. So you can retrieve strings, references, data, assets, ints, doubles, locations, dates as well as images and videos using the helper functions. If you store a image in the record you'll retrieve an optional UIImage when asking for the image, for a video you'll receive a url to a temporary local file which can be used in an AVPlayer. In that way you don't have to deal with conversion.

In order to set field types, you use the `set(type: Type, key: String)` functions. E.g: `record.set(string: "Hello World", key: "StringFieldKey")`

The fields do of course have to be specified in the cloud kit dashboard.

### CloudKitHandler

Cloud kit handler simply allows you to upload and delete records in the cloud database. There are two functions:

`upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?) -> Void)?)`

`delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?) -> Void)?)`

In the example project the upload function is used when a bar button item is touched. It uploads a record with a string field consisting of the count of amount of records plus one:

```
@IBAction func addItem(_ sender: UIBarButtonItem) {
    let record = CKRecord(recordType: CloudKitRecordType)
    record.set(string: "\(records.count + 1)", key: CloudKitTextField)
    upload(record: record) { [unowned self] (uploadedRecord) in
        if let uploadedRecord = record {
            self.records.insert(uploadedRecord, at: 0)
        }
    }
}
```

If an upload or deletion fails, the cloud kit handler will retry the operation after an interval. If the operation can't be completed after a few times, it'll call the cloud kit error handler.

### CloudKitSubscriber

- add remote-notification to UIBackgroundModes in info.plist
- register for remote notifications in app delegate and deal with them

## Todo

- [ ] Support type lists
- [ ] Make error handling more clear (e.g. in handler)

## Author

Simen Gangstad, simen.gangstad@me.com

## License

SwiftyCloudKit is available under the MIT license. See the LICENSE file for more info.
