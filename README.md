# SwiftyCloudKit

[![CI Status](http://img.shields.io/travis/simengangstad/SwiftyCloudKit.svg?style=flat)](https://travis-ci.org/simengangstad/SwiftyCloudKit) [![Version](https://img.shields.io/cocoapods/v/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![License](https://img.shields.io/cocoapods/l/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![Platform](https://img.shields.io/cocoapods/p/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit)

SwiftyCloudKit is a thin layer above Cloud Kit which makes it easy to implement cloud support into iOS/macOS/tvOS/watchOS apps. The library is structured into modules which can be used independently or together, all after need.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory. It is strongly recommended to run through the tutorial with the example project.

## Requirements

- Swift 4.0
- iOS: 10.0+
- macOS: 10.12+ (not tested)
- watchOS: 3.0+ (not tested)
- tvOS: 10.0+

## Installation

SwiftyCloudKit is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SwiftyCloudKit'
```

## Use

There are four submodules – or protocols – of SwiftyCloudKit: CloudKitFetcher, CloudKitHandler, CloudKitSubscriber and CloudKitErrorHandler.

### CloudKitErrorHandler

All the other submodules will call the error handler when an error occurs. Therefore it is required to conform to:

```
func handle(cloudKitError error: CKError) {
    // Handle errors
}
```

### CloudKitFetcher

The cloud kit fetcher protocol requires you to give it a database, a query and an fetch interval (how many records per batch). You also have to implement `parseResult(records: [CKRecord])`, which returns the records fetched, and `terminatingFetchRequest()`, which gets fired when a fetch request terminated because of some error.

In order to fetch from iCloud there's one prerequisite:
- Setup a record type in the cloud kit dashboard. In the example project a record type with the name "Record" and a string field type named "Text" is required.

We define a simple model:

```
// The key to our record
let CloudKitRecordType = "Record"
// The text field in our record
let CloudKitTextField = "Text"

// Model
var records = [CKRecord]()
```

And conform to the CloudKitFetcher protocol:

```
// Specify the database, could also be the publicCloudDatabase if one were to share
// data between multiple users, but in this case we fetch from our private iCloud database
var database: CKDatabase = CKContainer.default().privateCloudDatabase

var query: CKQuery? {
    // Specify that we want all the records stored in the database using the
    // "TRUEPREDICATE" predicate, and that we'll sort them by when they were created
    let query = CKQuery(recordType: CloudKitRecordType, predicate: NSPredicate(format: "TRUEPREDICATE"))
    query.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
    return query
}

// The amount of records we'll fetch for each request
var interval: Int = 10

// The cursor is an object which helps us keep track of which records we've fetched,
// and which records we are to fetch during the next batch. Can be set to nil to start fetching from the start.
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

Then call `fetch()` in e.g. viewDidAppear to fetch the records.

#### Accessing values

To access values from records you specify a field key, e.g. `let CloudKitTextField = "Text"` and acess it with the `string(_ key: String) -> String?` function, as seen in the table view data source in the example project:

```
override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    let cell = tableView.dequeueReusableCell(withIdentifier: "cellIdentifier", for: indexPath)
    // Notice how we access our field, with a call to string passing our constant for the text field type
    cell.textLabel?.text = records[indexPath.row].string(CloudKitTextField)
    return cell
}
```

There exist such helper functions for every type exept the list types. So you can retrieve strings, references, data, assets, ints, doubles, locations, dates as well as images and videos using the helper functions. If you store a image in the record you'll retrieve an optional UIImage when asking for the image, for a video you'll receive an optional URL to a temporary local file which can be used in an AVPlayer. In that way you don't have to deal with conversion.

In order to set field types, you use `set(type: Type, key: String)`. E.g: `record.set(string: "Hello World", key: "StringFieldKey")`

### CloudKitHandler

Cloud kit handler simply allows you to upload and delete records in the database. There are two functions:

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

If an upload or deletion fails, the cloud kit handler will retry the operation after a time interval. If the operation can't be completed after a few times, it'll call the cloud kit error handler.

### CloudKitSubscriber

A subscription is useful when there are multiple units having read and write access to the same data. An example would be an app which allows multiple users to collaborate on a spreadsheet. The subscription fires a notification when new data is appended, when data is deleted and when data is modified. The example project includes a demo concering this (be aware that the iOS simulator can't send these notifications, only receive, so test between two iOS devices).

The prerequisites for subscriptions are:
- Adding remote-notification to UIBackgroundModes in info.plist
- Specify some notification keys, e.g.:

```
public struct CloudKitNotifications {
    public static let NotificationReceived = "iCloudRemoteNotificationReceived"
    public static let NotificationKey = "Notification"
}
```

- Register for remote notifications in the app delegate, which is done the following way:

```
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    // Requests authorization to interact with the user when the external notification arrives
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
        if let error = error {
            print(error.localizedDescription)
        }
    }
    application.registerForRemoteNotifications()
    return true
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    // Decode the notification as a CKQueryNotification
    let ckqn = CKQueryNotification(fromRemoteNotificationDictionary: userInfo as! [String:NSObject])
    // Initiate a new notification with the notification keys
    let notification = Notification(name: NSNotification.Name(rawValue: CloudKitNotifications.NotificationReceived),
                                    object: self,
                                    userInfo: [CloudKitNotifications.NotificationKey: ckqn])
    // Post the notification
    NotificationCenter.default.post(notification)
}
```

The next step is to conform to the protocol:

```
// Specify that we want to listen to all updates concering the CloudKitRecordType
var subscription: CKQuerySubscription {
    let subscription = CKQuerySubscription(recordType: CloudKitRecordType,
                                           predicate: NSPredicate(format: "TRUEPREDICATE"),
                                           subscriptionID: "All records creation, deletions and updates",
                                           options: [.firesOnRecordCreation,
                                                     .firesOnRecordDeletion,
                                                     .firesOnRecordUpdate])

    let notificationInfo = CKNotificationInfo()
    notificationInfo.alertLocalizationKey = "New Records"
    notificationInfo.shouldBadge = true
    subscription.notificationInfo = notificationInfo

    return subscription
}

// Deal with the different types of subscription notifications
func handleSubscriptionNotification(ckqn: CKQueryNotification) {
    // If it's not our notification, why do anything?
    if ckqn.subscriptionID == subscription.subscriptionID {
        if let recordID = ckqn.recordID {
            switch ckqn.queryNotificationReason {
                case .recordCreated:
                database.fetch(withRecordID: recordID) { (record, error) in
                    if let error = error as? CKError {
                        self.handle(cloudKitError: error)
                    }
                    else {
                        if let record = record {
                            self.records.insert(record, at: 0)
                        }
                    }
                }

                case .recordDeleted:
                let index = self.records.index(where: { $0.recordID == recordID })
                self.records.remove(at: index!)

                case .recordUpdated:
                database.fetch(withRecordID: recordID) { (record, error) in
                    if let error = error as? CKError {
                        self.handle(cloudKitError: error)
                    }
                    else {
                        if let record = record {
                            let index = self.records.index(where: { $0.recordID == record.recordID })!
                            self.records[index] = record
                        }
                    }
                }
            }
        }
    }
}
```

And the final step is to subscribe to and unsubscribe from updates. This is necessary as subscribtions are quite expensive:

```
override func viewDidAppear(_ animated: Bool) {
    super.viewDidAppear(animated)
    subscribeToUpdates()
}

override func viewDidDisappear(_ animated: Bool) {
    super.viewDidDisappear(animated)
    unsubscribeToUpdates()
}
```

## Todo

- [ ] Support type lists

## Author

Simen Gangstad, simen.gangstad@me.com

## License

SwiftyCloudKit is available under the MIT license. See the LICENSE file for more info.

