import CloudKit

/**
 The cloud kit subscriber defines an interface for subscription updates, such as uploads and deletions from another devices.
 
 ## Example
 Given to devices logged into the same iCloud account with the same app installed. When device 1 uploads a record, device 2 will
 receive a notification and can append this record to its presenting data.
 
 
 - important
 One has to register for the subscription notifications in the app delegate:
 
         func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { (granted, error) in
                // Handle errors
            }
 
            application.registerForRemoteNotifications()
            return true
         }
 
 
 And post the notification to the observer:
 
        func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable : Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
 
            let ckqn = CKQueryNotification(fromRemoteNotificationDictionary: userInfo as! [String:NSObject])
 
            let notification = Notification(name: NSNotification.Name(rawValue: CloudKitNotifications.NotificationReceived), object: self, userInfo: [CloudKitNotifications.NotificationKey: ckqn])
            NotificationCenter.default.post(notification)
        }
 
 */
@available (iOS 10.0, *)
public protocol CloudKitSubscriber: CloudKitErrorHandler, PropertyStoring {
    
    /**
     The database the subscriber gets its updates from.
    */
    var database: CKDatabase { get }
    
    /**
     The terms of the subscription. Specify the query and the predicate here.
     */
    var subscription: CKQuerySubscription { get }

    /**
     Makes the subscriber listen to updates.
     
     - important:
    Subscription is expensive, so limit it to only when needed.
    */
    func subscribeToUpdates()
    
    /**
     Makes the subscriber stop listening to updates.
     
     - important:
     Make sure to unsubscribe when the subscription is not in use.
    */
    func unsubscribeToUpdates()
    
    /**
     Gets called when there are updates to the database within the terms specified by the query.
     
     - parameters:
        - ckqn: The notification fired, includes information about the update.
     
     - important:
    This function will be called from a global asynchronous thread. Switch to the main thread before you make changes to the UI, e.g. reloading the data in a table view.
    */
    func handleSubscriptionNotification(ckqn: CKQueryNotification)
}

/**
 Specifies the notification keys
 */
public struct CloudKitNotifications {
    public static let NotificationReceived = "iCloudRemoteNotificationReceived"
    public static let NotificationKey = "Notification"
}

private var observerKey: UInt8 = 0

public extension CloudKitSubscriber {

    internal typealias T = NSObjectProtocol?
    
    /**
     The observer, which listens to subscription notifications given with the notification key
    */
    private var cloudKitObserver: NSObjectProtocol? {
        get { return getAssociatedObject(&observerKey, defaultValue: nil as NSObjectProtocol?) }
        set { return setAssociatedObject(&observerKey, value: newValue) }
    }

    public func subscribeToUpdates() {
        database.save(subscription) { (savedSubscription, error) in
            if let error = error as? CKError {
                self.handle(cloudKitError: error)
            }
            else {
                print("Subscription to '\(self.subscription.subscriptionID)' successfull")
            }
        }

        cloudKitObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: CloudKitNotifications.NotificationReceived),
                                                                  object: nil,
                                                                  queue: OperationQueue.main) { notification in
                                                                    if let ckqn = notification.userInfo?[CloudKitNotifications.NotificationKey] as? CKQueryNotification {
                                                                        self.handleSubscriptionNotification(ckqn: ckqn)
                                                                    }
        }
    }

    public func unsubscribeToUpdates() {
        database.delete(withSubscriptionID: subscription.subscriptionID) { [unowned self] (removedSubscription, error) in
            if let error = error as? CKError {
                self.handle(cloudKitError: error)
            }
            else {
                print("Sucessful unsubscription from: \(self.subscription.subscriptionID)")
            }
        }

        NotificationCenter.default.removeObserver(self.cloudKitObserver as Any)
    }
}
