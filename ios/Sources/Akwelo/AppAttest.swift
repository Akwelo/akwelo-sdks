#if canImport(DeviceCheck) && canImport(CryptoKit)
import CryptoKit
import DeviceCheck
import Foundation

/// Best-effort App Attest token bound to the session (clientDataHash = SHA-256 of the token).
/// The page forwards it to Akwelo with the capture as a device signal. Akwelo verifies it with
/// Apple. Needs an Apple Developer team and the App Attest capability/entitlement. A new key is
/// generated on every call.
enum AppAttest {
    static func token(sessionToken: String) async -> String? {
        if #available(iOS 14.0, *) {
            let service = DCAppAttestService.shared
            guard service.isSupported else { return nil }
            do {
                let keyId = try await service.generateKey()
                let hash = Data(SHA256.hash(data: Data(sessionToken.utf8)))
                let attestation = try await service.attestKey(keyId, clientDataHash: hash)
                return keyId + "." + attestation.base64EncodedString()
            } catch {
                return nil
            }
        }
        return nil
    }
}
#endif
