//
//  Untitled.swift
//  SwitchHosts
//
//  Created by apple on 2026/7/16.
//
import LocalAuthentication
import Security

public enum KeychainManager {
    private static let service = "com.switchhosts.admin"

    static func hasStoredPassword() -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        return SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess
    }

    @discardableResult
    static func savePassword(_ password: String, requireBiometrics: Bool) -> Bool {
        deletePassword()
        guard let data = password.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]

        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    enum LoadResult {
        case success(String)
        case canceled
        case fallback
        case notFound
        case failed(String)
    }

    static func loadPassword(
        reason: String = "SwitchHosts 需要验证指纹以修改 /etc/hosts",
        useBiometrics: Bool
    ) -> LoadResult {
        // 支持指纹时，先用 LAContext 显式弹出 Touch ID 作为读取门禁
        if useBiometrics {
            let context = LAContext()
            var error: NSError?
            guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
                // 指纹不可用，直接静默读取
                return loadPasswordDirect()
            }

            let semaphore = DispatchSemaphore(value: 0)
            var authOutcome: LoadResult = .canceled
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { success, evalError in
                if success {
                    authOutcome = .success("")
                } else if let laError = evalError as? LAError {
                    switch laError.code {
                    case .userCancel, .systemCancel, .appCancel:
                        authOutcome = .canceled
                    case .userFallback:
                        // 用户点击「使用密码」，回退到密码输入框
                        authOutcome = .fallback
                    default:
                        authOutcome = .fallback
                    }
                } else {
                    authOutcome = .fallback
                }
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .distantFuture)

            switch authOutcome {
            case .success:
                return loadPasswordDirect()
            case .canceled:
                return .canceled
            case .fallback:
                return .fallback
            default:
                return authOutcome
            }
        }

        return loadPasswordDirect()
    }

    private static func loadPasswordDirect() -> LoadResult {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName(),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let password = String(data: data, encoding: .utf8) else {
                return .failed("无法解析钥匙串密码")
            }
            return .success(password)
        case errSecItemNotFound:
            return .notFound
        default:
            return .failed("钥匙串读取失败（错误码: \(status)）")
        }
    }

    static func deletePassword() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: NSUserName()
        ]
        SecItemDelete(query as CFDictionary)
    }
}
