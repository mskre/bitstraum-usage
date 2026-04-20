import Foundation
import LocalAuthentication
import Security

@main
struct AppCredentialStoreTouchIDTests {
    static func main() throws {
        let store = AppCredentialStore(service: "com.bitstraum.usage.tests")
        let query = try store.makeProtectedItem("claude", data: Data("x".utf8))

        guard query[kSecAttrAccessControl as String] != nil else {
            fatalError("Expected protected item to include access control")
        }
        guard query[kSecAttrAccessible as String] == nil else {
            fatalError("Expected protected item to rely on access control instead of a separate accessible attribute")
        }

        let context = LAContext()
        let readQuery = store.makeProtectedReadQuery("claude", context: context)

        guard readQuery[kSecUseAuthenticationContext as String] != nil else {
            fatalError("Expected protected read query to include LAContext")
        }
    }
}
