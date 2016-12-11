//
//  GAuthorizer.swift
//  Neatly packaged authorization via Google in Swift using GTMAppAuth.
//
//  Created by J. Marco Bremer (marco@bluemedialabs.com) on 2016-12-11.
//  Inspired by: https://github.com/google/GTMAppAuth/blob/master/Example-iOS/Source/GTMAppAuthExampleViewController.m
//
//  To the extent possible under law, the author(s) have dedicated all copyright and related
//  and neighboring rights to this software to the public domain worldwide. This software is
//  distributed without any warranty.
//  You should have received a copy of the CC0 Public Domain Dedication along with this
//  software. If not, see <http://creativecommons.org/publicdomain/zero/1.0/>
//

import AppAuth
import GTMAppAuth
import GTMOAuth2

// Replace this by whatever logging framework you prefer:
//import XCGLogger
//let log = XCGLogger.default



/// Get the singleton, `addScope`s as desired, set an `authorizationCompletion` (preferrably one that's either in the background or relies on the same view controller that issued the authorization request and is thus the one the app returns to when that, external, request completes), call `authorize(in)` from a given view controller. The authorization in Safari & Co will then reenter the app in the AppDelegate and cause `continueAuthorization(with)` to be called. See the minimal code that you have to add to `AppDelegate` for this.
class GAuthorizer: NSObject, OIDAuthStateChangeDelegate, OIDAuthStateErrorDelegate {
    
    // I usually define this somewhere central...
    static let KeychainPrefix   = "com.bluemedialabs.myproject."  // REPLACE this with anything.
    static let KeychainItemName = KeychainPrefix + "GoogleAuthorization"
    
    static private var singleton: GAuthorizer?
    static var shared: GAuthorizer {
        if singleton == nil {
            singleton = GAuthorizer()
        }
        return singleton!
    }
    
    // To be set by any user of this object, if they want to be informed about an authorization result. Good, in particular, to take the newly adjusted authorizer and set it in whatever service one is doing the authorization for.
    var authorizationCompletion: ((Bool) -> Void)?
    // The entity that, for example, the Google Drive service needs to do its jobs.
    private(set) var authorization: GTMAppAuthFetcherAuthorization? = nil
    // The callback hook for authorization after app reentry in AppDelegate, used and reset in continueAuthorization(with).
    private var currentAuthorizationFlow: OIDAuthorizationFlowSession?
    private var scopes = [OIDScopeOpenID, OIDScopeProfile]
    
    
    private override init() {
        super.init()
    }
    
    
    /// Adds another aspect for which to authorize for to the base set of scopes (which are: OIDScopeOpenID, OIDScopeProfile).
    /// Example: Add `kGTLAuthScopeDriveFile` to authorize for: 'Create new files and access just these files in the user's Google Drive account'. (Requires the Google Drive framework, too. The variable is from GTLDriveConstants.h in there.)
    func addScope(_ scope: String) {
        if scopes.index(of: scope) == nil {
            scopes.append(scope)
        }
    }
    
    
    // To be called to initiate authorization, for instance, following a button tap in the UI. The `authWithAutoCodeExchange` from the GTMAppAuth Objective-C example.
    func authorize(in presentingViewController: UIViewController) {
        log.debug("Starting Google authentication...")
        let issuer = URL(string: Config.GoogleAuthOIDCIssuer)!
        let redirectURI = URL(string: Config.GoogleAuthRedirectURI)!
        log.debug("Fetching configuration for issuer: \(issuer)")
        
        // discovers endpoints
        OIDAuthorizationService.discoverConfiguration(forIssuer: issuer) {
            (configuration: OIDServiceConfiguration?, error: Error?) in
            
            if configuration == nil {
                log.warning("Error retrieving discovery document: \(error?.localizedDescription)")
                self.setAuthorization(nil)
                return
            }
            log.debug("Got configuration: \(configuration!)")
            
            // builds authentication request
            let request: OIDAuthorizationRequest = OIDAuthorizationRequest(configuration: configuration!, clientId: Config.GoogleAuthClientID, scopes: self.scopes, redirectURL: redirectURI, responseType: OIDResponseTypeCode, additionalParameters: nil)
            // (The 'kGTLAuthScopeDriveFile' is from GTLDriveConstants.h and just an attempt to add GDrive file access to the authorization scope...)
            
            // performs authentication request
            //            let appDelegate: AppDelegate = UIApplication.shared.delegate as! AppDelegate
            // (Swift can't extend AppDelegate by a var. So, let's keep things simple and use a global variable instead.)
            log.debug("Initiating authorization request with scope: \(request.scope)")
            
            self.currentAuthorizationFlow = OIDAuthState.authState(byPresenting: request, presenting: presentingViewController) {
                (authState: OIDAuthState?, error: Error?) in
                log.debug("Processing authorization status from external callback...")
                if let authState = authState {
                    let authorization: GTMAppAuthFetcherAuthorization = GTMAppAuthFetcherAuthorization(authState: authState)
                    self.setAuthorization(authorization)
                    log.debug("Received authorization tokens. Access token: \(authState.lastTokenResponse?.accessToken)")
                } else {
                    self.setAuthorization(nil)
                    if let error = error {
                        log.warning("Authorization error: \(error.localizedDescription)")
                    } else {
                        log.warning("No proper authorization state, but also no error!?...")
                    }
                }
            }
        }
    }
    
    
    
    /// Returns true, iff the give URL matched a Google authorization flow in progress and was consumed properly.
    func continueAuthorization(with url: URL) -> Bool {
        log.debug("Checking whether URL '\(url)' continues a pending Google authorization...")
        if let authFlow = currentAuthorizationFlow {
            log.debug("URL callback could be for Google authorization...")
            //            guard let viewController = Global.athletesViewController else {
            //                log.warning("URL callback from Google with no view controller to return to set!?? Ignoring the callback...")
            //                return false
            //            }
            //            log.debug("..the view controller to report on the result is there...")
            if authFlow.resumeAuthorizationFlow(with: url) {
                log.info("Google authorization apparently succeeded...")
                // IMPORTANT: Notice that, if the given URL is right for us here, but authentication fails or is negative, then authState::didEncounterAuthorizationError should be called internally...
                currentAuthorizationFlow = nil
                if let completion = authorizationCompletion {
                    completion(true)
                }
            } else {
                // ..we'll not end up here in this case!
                //log.info("Google authorization failed somehow, or the callback was no authorization in progress")
                log.debug("Not a Google authorization URL it seems.")
                //viewController.reportExportSuccess(forOption: .googleDrive, success: false) -- Wrong!
            }
            return true
        } else {
            log.debug("There doesn't seem to be any pending authorization request")
            return false
        }
        
    }
    
    /// Preserves the current authorization state both in memory and keychain.
    private func setAuthorization(_ authorization: GTMAppAuthFetcherAuthorization?) {
        if self.authorization == nil || !self.authorization!.isEqual(authorization) {
            self.authorization = authorization
            saveState()
        }
    }
    
    func isAuthorized() -> Bool {
        if let auth = authorization {
            return auth.canAuthorize()
        } else {
            return false
        }
    }
    
    
    // Used internally to save the current authorization state.
    private func saveState() {
        assert(authorization != nil)
        let keychainItemName = GAuthorizer.KeychainItemName
        if authorization!.canAuthorize() {
            GTMAppAuthFetcherAuthorization.save(authorization!, toKeychainForName: keychainItemName)
        } else {
            GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: keychainItemName)
        }
    }
    
    /// To be used in particular to load the initial authorization state on app start.
    func loadState() {
        let keychainItemName = GAuthorizer.KeychainItemName
        if let authorization: GTMAppAuthFetcherAuthorization = GTMAppAuthFetcherAuthorization(fromKeychainForName: keychainItemName) {
            setAuthorization(authorization)
        } else {
            log.debug("...")
        }
    }
    
    /// Clears the keychain from any Google authorization data. This is useful, for example, after an app reinstallation or for testing where an outdated authorization state can cause trouble or prevent certain tests from going through.
    func resetState() {
        GTMAppAuthFetcherAuthorization.removeFromKeychain(forName: GAuthorizer.KeychainItemName)
        // As keychain and cached authorization token are meant to be in sync, we also have to:
        setAuthorization(nil)
    }
    
    
    // MARK: - OIDAuthStateChangeDelegate
    
    func didChange(_ state: OIDAuthState) {
        log.debug("Google authorization state chanded to \(state)")
        // (..whatever the significance of this. Are we supposed to do something with this information?)
    }
    
    
    // MARK: - OIDAuthStateErrorDelegate
    
    // This seems to be the hook being called when authentication, especially after the URL callback from outside, fails. Notice that the `resumeAuthorizationFlow` function that lets us try to finish authorization, doesn't let us distinguish between failed and wasn't-a-URL-for-us otherwise!
    func authState(_ state: OIDAuthState, didEncounterAuthorizationError error: Error) {
        log.warning("Encountered Google authorization error that the user should be alerted to: \(error)")
        if currentAuthorizationFlow != nil {
            // Looks like there is an authorization in progress... which failed.
            currentAuthorizationFlow = nil
            // We are not authorized anymore this says, right!? So...
            setAuthorization(nil)
            if let completion = authorizationCompletion {
                completion(false)
            }
        }
    }
    
} // GAuthorizer
