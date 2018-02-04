import CloudKit

@available (iOS 10.0, *)
public protocol CloudKitSubscriber: CloudKitErrorHandler {
    var database: CKDatabase { get }
    var cloudKitObserver: NSObjectProtocol? { get set }
    var subscription: CKQuerySubscription { get }

    func subscribeToUpdates()
    func unsubscribeToUpdates()
    func handleSubscriptionNotification(ckqn: CKQueryNotification)
}

private var observerKey: UInt8 = 0

func associatedObject(base: AnyObject, key: UnsafePointer<UInt8>, initialiser: () -> AnyObject?) -> AnyObject? {
    if let associated = objc_getAssociatedObject(base, key) { return associated as AnyObject }
    let associated = initialiser()
    objc_setAssociatedObject(base, key, associated, .OBJC_ASSOCIATION_RETAIN)
    return associated
}

func associateObject(base: AnyObject, key: UnsafePointer<UInt8>, value: AnyObject) {
    objc_setAssociatedObject(base, key, value, .OBJC_ASSOCIATION_RETAIN)
}

@available (iOS 10.0, *)
public extension CloudKitSubscriber {

    public var cloudKitObserver: NSObjectProtocol? {
        get { return associatedObject(base: self, key: &observerKey) { return nil } as! NSObjectProtocol? }
        set { associateObject(base: self, key: &observerKey, value: newValue as AnyObject) }
    }

    public func subscribeToUpdates() {

        database.save(subscription) { (savedSubscription, error) in
            if let error = error as? CKError {
                self.handleCloudKitError(error: error)
            }
            else {
                print("Subscription to '\(self.subscription.subscriptionID)' successfull")
            }
        }

        cloudKitObserver = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: CloudKitNotifications.NotificationReceived),
                                                                  object: nil,
                                                                  queue: OperationQueue.main,
                                                                  using: {notification in
                                                                    if let ckqn = notification.userInfo?[CloudKitNotifications.NotificationKey] as? CKQueryNotification {
                                                                        self.handleSubscriptionNotification(ckqn: ckqn)
                                                                    }
        })
    }

    public func unsubscribeToUpdates() {
        database.delete(withSubscriptionID: subscription.subscriptionID) { [unowned self] (removedSubscription, error) in
            if let error = error as? CKError {
                self.handleCloudKitError(error: error)
            }
            else {
                print("Sucessful unsubscription from: \(self.subscription.subscriptionID)")
            }
        }

        NotificationCenter.default.removeObserver(self.cloudKitObserver as Any)
    }
}
