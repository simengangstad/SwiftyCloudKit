import CloudKit

public protocol CloudKitErrorHandler: class {
    func handleCloudKitError(error: CKError)
}
