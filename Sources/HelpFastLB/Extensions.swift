
import Foundation

extension Notification.Name {
    static let internetConnectionRestored = Notification.Name("internetConnectionRestored")
    public static let apnsTokenReceived = Notification.Name("apnsTokenReceived")
    public static let succesfullUpdate = Notification.Name("succesfullUpdate")
    public static let failedUpdate = Notification.Name("failedUpdate")
}



extension String {
    func decodePercentEncoding() -> String {
        var result = ""
        var i = self.startIndex
        
        while i < self.endIndex {
            if self[i] == "%" && i < self.index(self.endIndex, offsetBy: -2) {
                let start = self.index(i, offsetBy: 1)
                let end = self.index(i, offsetBy: 3)
                let hexString = String(self[start..<end])
                
                if let hexValue = UInt32(hexString, radix: 16),
                   let unicode = UnicodeScalar(hexValue) {
                    result.append(Character(unicode))
                    i = end
                } else {
                    return ""
                }
            } else {
                result.append(self[i])
                i = self.index(after: i)
            }
        }
        
        return result
    }
}
