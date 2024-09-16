import Flutter
import UIKit
import GameKit
import os
import FirebaseAuth

public class SwiftGameServicesFirebaseAuthPlugin: NSObject, FlutterPlugin {
    
    var viewController: UIViewController? {
        return UIApplication.shared.windows.first?.rootViewController
    }
    
    @available(iOS 13.0, *)
    private func getCredentialsAndSignIn(result: @escaping (Bool, FlutterError?) -> Void) {
        GameCenterAuthProvider.getCredential { cred, error in
            if let error = error {
                result(false, FlutterError(code: "get_gamecenter_credentials_failed",
                                           message: "Failed to get GameCenter credentials",
                                           details: error.localizedDescription))
                return
            }
            guard let cred = cred else {
                result(false, FlutterError(code: "gamecenter_credentials_null",
                                           message: "Failed to get GameCenter credentials",
                                           details: "Credential are null"))
                return
            }
            Auth.auth().signIn(with: cred) { (authResult, error) in
                if let error = error {
                    result(false, FlutterError(code: "firebase_signin_failed",
                                               message: "Failed to sign in to Firebase",
                                               details: error.localizedDescription))
                    return
                }
                result(true, nil)
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func getCredentialsAndLink(user: User, forceSignInIfCredentialAlreadyUsed: Bool, result: @escaping (Bool, FlutterError?) -> Void) {
        GameCenterAuthProvider.getCredential { cred, error in
            if let error = error {
                result(false, FlutterError(code: "get_gamecenter_credentials_failed",
                                           message: "Failed to get GameCenter credentials",
                                           details: error.localizedDescription))
                return
            }
            guard let cred = cred else {
                result(false, FlutterError(code: "gamecenter_credentials_null",
                                           message: "Failed to get GameCenter credentials",
                                           details: "Credential are null"))
                return
            }
            user.link(with: cred) { (authResult, error) in
                if let error = error {
                    guard let errorCode = AuthErrorCode(rawValue: error._code) else {
                        self.log(message: "Unmatched Firebase error: \(error.localizedDescription)")
                        result(false, FlutterError(code: "unknown_error",
                                                   message: "An unknown error occurred",
                                                   details: error.localizedDescription))
                        return
                    }
                    let code = errorCode == .credentialAlreadyInUse ? "ERROR_CREDENTIAL_ALREADY_IN_USE" : "\(errorCode.rawValue)"
                    if code == "ERROR_CREDENTIAL_ALREADY_IN_USE" && forceSignInIfCredentialAlreadyUsed {
                        do {
                            try Auth.auth().signOut()
                            Auth.auth().signIn(with: cred) { (authResult, error) in
                                if let error = error {
                                    result(false, FlutterError(code: "firebase_signin_failed",
                                                               message: "Failed to sign in to Firebase",
                                                               details: error.localizedDescription))
                                    return
                                }
                                result(true, nil)
                            }
                        } catch let signOutError as NSError {
                            result(false, FlutterError(code: "firebase_signout_failed",
                                                       message: "Failed to sign out from Firebase",
                                                       details: signOutError.localizedDescription))
                        }
                    } else {
                        result(false, FlutterError(code: code,
                                                   message: "Failed to link credentials to Firebase User",
                                                   details: error.localizedDescription))
                    }
                    return
                } else {
                    result(true, nil)
                }
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func signInWithGameCenter(result: @escaping (Bool, FlutterError?) -> Void) {
        let player = GKLocalPlayer.local
        if player.isAuthenticated {
            self.getCredentialsAndSignIn(result: result)
        } else {
            player.authenticateHandler = { vc, error in
                if let vc = vc {
                    DispatchQueue.main.async {
                        self.viewController?.present(vc, animated: true, completion: nil)
                    }
                } else if player.isAuthenticated {
                    self.getCredentialsAndSignIn(result: result)
                } else {
                    result(false, FlutterError(code: "no_player_detected",
                                               message: "No player detected on this phone",
                                               details: error?.localizedDescription))
                }
            }
        }
    }
    
    @available(iOS 13.0, *)
    private func linkGameCenterCredentialsToCurrentUser(forceSignInIfCredentialAlreadyUsed: Bool, result: @escaping (Bool, FlutterError?) -> Void) {
        let player = GKLocalPlayer.local
        guard let user = Auth.auth().currentUser else {
            result(false, FlutterError(code: "no_user_sign_in",
                                       message: "No User signed in to Firebase, impossible to link any credentials",
                                       details: nil))
            return
        }
        for provider in user.providerData {
            if provider.providerID == "gc.apple.com" {
                self.log(message: "User already linked to Game Center")
                result(true, nil)
                return
            }
        }
        if player.isAuthenticated {
            self.getCredentialsAndLink(user: user, forceSignInIfCredentialAlreadyUsed: forceSignInIfCredentialAlreadyUsed, result: result)
        } else {
            player.authenticateHandler = { vc, error in
                if let vc = vc {
                    DispatchQueue.main.async {
                        self.viewController?.present(vc, animated: true, completion: nil)
                    }
                } else if player.isAuthenticated {
                    self.getCredentialsAndLink(user: user, forceSignInIfCredentialAlreadyUsed: forceSignInIfCredentialAlreadyUsed, result: result)
                } else {
                    result(false, FlutterError(code: "no_player_detected",
                                               message: "No player detected on this phone",
                                               details: error?.localizedDescription))
                }
            }
        }
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        if #available(iOS 13.0, *) {
            switch call.method {
            case "sign_in_with_game_service":
                signInWithGameCenter() { success, error in
                    if let error = error {
                        result(error)
                    } else {
                        result(success)
                    }
                }
            case "link_game_services_credentials_to_current_user":
                var forceSignInIfCredentialAlreadyUsed = false
                if let args = call.arguments as? [String: Any] {
                    forceSignInIfCredentialAlreadyUsed = args["force_sign_in_credential_already_used"] as? Bool ?? false
                }
                linkGameCenterCredentialsToCurrentUser(forceSignInIfCredentialAlreadyUsed: forceSignInIfCredentialAlreadyUsed) { success, error in
                    if let error = error {
                        result(error)
                    } else {
                        result(success)
                    }
                }
            default:
                self.log(message: "Unknown method called: \(call.method)")
                result(FlutterMethodNotImplemented)
            }
        } else {
            result(FlutterError(code: "iOS_version_not_supported",
                                message: "iOS 13.0 or newer is required.",
                                details: nil))
        }
    }
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "game_services_firebase_auth", binaryMessenger: registrar.messenger())
        let instance = SwiftGameServicesFirebaseAuthPlugin()
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    private func log(message: String) {
        if #available(iOS 10.0, *) {
            os_log("%@", message)
        } else {
            print(message)
        }
    }
}
