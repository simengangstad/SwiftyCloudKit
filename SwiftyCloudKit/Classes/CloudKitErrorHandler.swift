import CloudKit

protocol CloudKitErrorHandler: class {
    func handleCloudKitError(error: CKError)
}
