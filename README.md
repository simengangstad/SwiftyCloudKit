# SwiftyCloudKit

[![CI Status](http://img.shields.io/travis/simengangstad/SwiftyCloudKit.svg?style=flat)](https://travis-ci.org/simengangstad/SwiftyCloudKit) [![Version](https://img.shields.io/cocoapods/v/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![License](https://img.shields.io/cocoapods/l/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit) [![Platform](https://img.shields.io/cocoapods/p/SwiftyCloudKit.svg?style=flat)](http://cocoapods.org/pods/SwiftyCloudKit)

SwiftyCloudKit is a thin layer above Cloud Kit which makes it easy to implement cloud support into iOS/macOS/tvOS/watchOS apps.

## Example

To run the example project, clone the repo, and run `pod install` from the Example directory. It is strongly recommended to run through the tutorial with the example project.

## Requirements

- Swift 4.0
- iOS: 10.0+
- macOS: 10.12+ (not tested)
- watchOS: 3.0+ (not tested)
- tvOS: 10.0+ (not tested)

## Installation

SwiftyCloudKit is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'SwiftyCloudKit'
```

## Use

SwiftyCloudKit consists of two submodules: CloudKitHandler and CloudKitSubscriber. For more information on how these are implemented read further on, see the example project or the documentation in the respective files in the library.

### CloudKitHandler

The cloud kit handler fetches records from iCloud and allows you to upload records to the iCloud database and remove records from it. Remember to set up a record type at the [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard) first. The protocol requires you to implement five variables (read more about these in the documentation or in the example project), which define how the fetch is executed. If `offlineSupport` is set to true, the library will handle the cases where the device is offline and store the records temporarily locally, and upload them once internet connection is present.

```swift

var database: CKDatabase
var query: CKQuery?
var interval: Int
var cursor: CKQueryCursor?
var offlineSupport: Bool
```

Then simply call the fetch function in e.g. viewDidAppear to fetch the records:

```swift
fetch(withCompletionHandler: { (records, error) in
    // Do something with the fetched records.
})
```

#### Uploading and deleting records

Uploading and deleting records are done with the following methods. If an upload or deletion operation fails because of an iCloud error, the error included in the completion handler will be a CKError. If the operation fails because the library didn't detect an internet connection and failed to save or delete locally, it will return a LocalStorageError.

```swift
upload(record: CKRecord, withCompletionHandler completionHandler: ((CKRecord?, Error?) -> Void)?)
```
```swift
delete(record: CKRecord, withCompletionHandler completionHandler: ((CKRecordID?, Error?) -> Void)?)
```

An example:
```swift
let record = CKRecord(recordType: MyRecordType)
record.set(string: "Hello World", key: MyStringKey)
upload(record: record, withCompletionHandler: { [unowned self] (record, error) in
    // Do something with the uploaded record
})
delete(record: record, withCompletionHandler: { [unowned self] (recordID, error) in
    // Do something when the record is deleted
})
```

#### Accessing and setting values of records

There exist helper functions for every type supported by CloudKit. So you can retrieve and set strings, references, data, assets, ints, doubles, locations, dates, lists of the these types, as well as images and videos using the helper functions. If you store a image in the record you'll retrieve an optional UIImage when asking for the image, for a video you'll receive an optional URL to a temporary local file which can be used in an AVPlayer. In that way you don't have to deal with conversion. *Note: As the videos are stored locally as cache, it's necessary to clear the cache at times. Call `deleteLocalVideos()` in e.g. `applicationWillTerminate(_ application: UIApplication)` in the AppDelegate order to remove them.*

To retrieve values, you use `value(_ key: String)`. E.g.:
```swift
let myString = record.string(MyStringKey)
```

In order to set values, you use `set(value: Value, key: String)`. E.g:
```swift
record.set(string: "Hello World", key: MyStringKey)
```


### CloudKitSubscriber

A subscription is useful when there are multiple units having read and write access to the same data. An example would be an app which allows multiple users to collaborate on a spreadsheet. The subscription fires a notification when new data is appended, when data is deleted and when data is modified. The example project includes a demo concerning this (be aware that the iOS simulator can't send these notifications, only receive, so test between two iOS devices).

The prerequisites for subscriptions are:
- Adding remote-notification to UIBackgroundModes in info.plist
- Register for remote notifications in the app delegate and post notifications around the app when we receive a push notification, which is done the following way:

```swift
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
        // Handle error
    }
    application.registerForRemoteNotifications()
    return true
}

func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    let ckqn = CKQueryNotification(fromRemoteNotificationDictionary: userInfo as! [String:NSObject])
    let notification = Notification(name: NSNotification.Name(rawValue: MyNotificationReceivedKey),
                                    object: self,
                                    userInfo: [MyNotificationKey: ckqn])
    NotificationCenter.default.post(notification)
}
```

The next step is to conform to the protocol:

```swift
var subscription: CKQuerySubscription

func handleSubscriptionNotification(ckqn: CKQueryNotification) {}
```

And the final step is to subscribe to and unsubscribe from updates. This is necessary as subscribtions are quite expensive:

```swift
// Call in e.g. viewDidAppear
subscribeToUpdates()

// Call in e.g. viewDidDisappear
unsubscribeToUpdates()
```

## Todo

- [x] Support type lists
- [x] Update readme
- [x] Include local and offline capabilities into the library
- [ ] Add tests
- [ ] Add image support for macOS
- [ ] Test on tvOS, watchOS and macOS

## Author

Simen Gangstad, simen.gangstad@me.com

## License

SwiftyCloudKit is available under the MIT license. See the LICENSE file for more info.
