import CloudKit
import ObjectiveC

public protocol PropertyStoring {
    associatedtype T
    func getAssociatedObject(_ key: UnsafePointer<UInt8>, defaultValue: T) -> T
    func setAssociatedObject(_ key: UnsafePointer<UInt8>, value: T)
}

public extension PropertyStoring {
    public func getAssociatedObject(_ key: UnsafePointer<UInt8>, defaultValue: T) -> T {
        guard let value = objc_getAssociatedObject(self, key) as? T else {
            return defaultValue
        }
        return value
    }
    
    public func setAssociatedObject(_ key: UnsafePointer<UInt8>, value: T) {
        return objc_setAssociatedObject(self, key, value, .OBJC_ASSOCIATION_RETAIN)
    }
}

public extension CKRecord {
    
    public func image(_ key: String) -> UIImage? {
        return (self[key] as? CKAsset)?.image
    }

    public func set(image: UIImage?, key: String)  {
        if let image = image {
            do {
                self[key] = try CKAsset(image: image)
            }
            catch let error {
                print("Error creating CKAsset from image: \(error)")
            }
        }
        else {
            self[key] = nil
        }
    }

    public func video(_ key: String) -> URL? {
        return (self[key] as? CKAsset)?.video(withFilename: "\(recordID)\(key).mov")
    }

    public func set(video: URL?, key: String) {
        if let video = video {
            self[key] = CKAsset(fileURL: video)
        }
        else {
            self[key] = nil
        }
    }

    public func string(_ key: String) -> String? {
        return self[key] as? String
    }

    public func set(string: String?, key: String) {
        if let string = string {
            self[key] = string as CKRecordValue
        }
    }

    public func reference(_ key: String) -> CKReference? {
        return self[key] as? CKReference
    }

    public func set(reference: CKReference?, key: String) {
        if let reference = reference {
            self[key] = reference as CKRecordValue
        }
    }

    public func data(_ key: String) -> Data? {
        return self[key] as? Data
    }

    public func set(data: Data?, key: String) {
        if let data = data {
            self[key] = data as CKRecordValue
        }
    }

    public func asset(_ key: String) -> CKAsset? {
        return self[key] as? CKAsset
    }

    public func set(asset: CKAsset?, key: String) {
        if let asset = asset {
            self[key] = asset as CKRecordValue
        }
    }

    public func int(_ key: String) -> Int? {
        return self[key] as? Int
    }

    public func set(int: Int?, key: String) {
        if let int = int {
            self[key] = int as CKRecordValue
        }
    }

    public func double(_ key: String) -> Double? {
        return self[key] as? Double
    }

    public func set(double: Double?, key: String) {
        if let double = double {
            self[key] = double as CKRecordValue
        }
    }

    public func location(_ key: String) -> CLLocation? {
        return self[key] as? CLLocation
    }

    public func set(location: CLLocation?, key: String) {
        if let location = location {
            self[key] = location as CKRecordValue
        }
    }

    public func date(_ key: String) -> Date? {
        return self[key] as? Date
    }

    public func set(date: Date?, key: String) {
        if let date = date {
            self[key] = date as CKRecordValue
        }
    }
}

public struct CloudKitNotifications {
    public static let NotificationReceived = "iCloudRemoteNotificationReceived"
    public static let NotificationKey = "Notification"
}


public enum ImageFileType {
    case JPG(compressionQuality: CGFloat)
    case PNG

    var fileExtension: String {
        switch self {
        case .JPG(_):
            return ".jpg"
        case .PNG:
            return ".png"
        }
    }
}

public enum ImageError: Error {
    case UnableToConvertImageToData
}

public extension CKAsset {
    public convenience init(image: UIImage, fileType: ImageFileType = .JPG(compressionQuality: 70)) throws {
        let url = try image.saveToTempLocationWithFileType(fileType: fileType)
        self.init(fileURL: url)
    }

    public var image: UIImage? {
        guard let data = NSData(contentsOf: fileURL), let image = UIImage(data: data as Data) else { return nil }
        return image
    }

    public func video(withFilename filename: String) -> URL? {
        return Data.retrieveOrCreateFile(withDataURL: fileURL, andFileName: "\(filename).mov", recreateIfFileExists: false)
    }
}

public extension Data {
    static func retrieveOrCreateFile(withDataURL fileURL: URL, andFileName fileName: String, recreateIfFileExists recreate: Bool) -> URL? {
        let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
        let destinationPath = NSURL(fileURLWithPath: documentsPath).appendingPathComponent("\(fileName).mov", isDirectory: false)

        if !recreate && FileManager.default.fileExists(atPath: destinationPath!.path) {
            return destinationPath
        }

        do {
            if FileManager.default.createFile(atPath: destinationPath!.path, contents: try Data(contentsOf: fileURL), attributes: nil) {
                return destinationPath!
            }
        }
        catch let error {
            print("Error creating file: \(error)")
            return nil
        }

        return nil
    }
}

public extension UIImage {
    fileprivate func saveToTempLocationWithFileType(fileType: ImageFileType) throws -> URL {
        let imageData: NSData?

        switch fileType {
        case .JPG(let quality):
            imageData = UIImageJPEGRepresentation(self, quality) as NSData?
        case .PNG:
            imageData = UIImagePNGRepresentation(self) as NSData?
        }
        guard let data = imageData else {
            throw ImageError.UnableToConvertImageToData
        }

        let filename = ProcessInfo.processInfo.globallyUniqueString + fileType.fileExtension
        let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
        try data.write(to: url, options: .atomicWrite)

        return url
    }
}
