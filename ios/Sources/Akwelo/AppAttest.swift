#if canImport(DeviceCheck) && canImport(CryptoKit)
import CryptoKit
import DeviceCheck
import Foundation

/// Best-effort App Attest token bound to the session (clientDataHash = SHA-256 of the token).
///
/// TODO(akwelo): needs an Apple Developer team, the App Attest capability/entitlement, and
/// Akwelo backend support for attestation-object verification and key registration. The key is
/// generated per call here; production should persist the keyId in the Keychain and send an
/// assertion after the first attestation. Untested until those accounts exist.
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
