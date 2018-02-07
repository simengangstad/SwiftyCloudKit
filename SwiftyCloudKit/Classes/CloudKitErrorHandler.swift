import CloudKit

/**
 The protocol defining the way errors are handled within the swifty cloud kit library
 */
public protocol CloudKitErrorHandler: class {
    
    /**
     Handles errors occured within the swifty cloud kit library
     
     - parameters:
        - cloudKitError: The error occurred.
     
     - important:
     It is a recommended to use a switch statement on error.code to deal with the different types of
     errors. See the documentation for [CKError](https://developer.apple.com/documentation/cloudkit/ckerror) for more
     information.
     
     This function will be called whenever any aspect of the cloud kit cycle fails.
     */
    func handle(cloudKitError error: CKError)
}
