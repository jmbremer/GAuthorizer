# GAuthorizer

Neatly packaged OAuth authorization via Google in Swift using GTMAppAuth. For using APIs such as the Google Drive API once Google disallows the use of embedded/web views for OAuth authorization. The core heavily leans on and even references [Google's example in Objective-C](https://github.com/google/GTMAppAuth/blob/master/Example-iOS/Source/GTMAppAuthExampleViewController.m).

Or: Just an example to get GTMAppAuth to work in Swift as a replacement of [Google's official iOS Quickstart guide](https://developers.google.com/drive/ios/quickstart?ver=swift) (to do authorization for the Google Drive API in this case). As of mid December 2016, Google's' guide is outdated and will NOT work for new projects or stop working for existing, untouched projects around April 2017. Also, see my Stackoverflow answer [here](http://stackoverflow.com/a/41059043/893774).

## Installation

The code is just an example and meant to be studied or copied and reused instead of adding yet another layer of frameworks to this (for the non-expert) already quite complex hierarchy of frameworks on AppAuth and GTMAppAuth.

### CocoaPods
Remove prior pods for authorization like `GTMOAuth2` or the low-level `AppAuth`. The podfile should have just this:

    pod 'GTMAppAuth'

For accessing Google Drive files, I also have:

    pod 'GoogleAPIClient/Drive', '~> 1.0.2'


## Usage

Here is what I did to get from my old authorizer code related to my app's' Google Drive export to a working authorization with the latest non-web-view version.

1. Add GtmAppAuth pod to the podfile.
2. Remove AppAuth2 and the likes from the podfile.
3. Run `pod install`.
3. Add my new GAuthorizer class.
4. Adapt the code as follows.

On app initialization, I run `setup()`:
```
import GoogleAPIClient
import AppAuth
import GTMAppAuth

var googleDriveService = GoogleDriveDService()  // The kinda global GDrive service object.

func setup() {
    let googleAuthorizer = GAuthorizer.shared
    googleAuthorizer.addScope(kGTLAuthScopeDriveFile)
    // (kGTLAuthScopeDriveFile is defined in GTLDriveConstants.h)
    googleAuthorizer.loadState()
    // (loadState() may actually find the authorization there already, so the following makes
    //  sense, but may still result in a service.authorizer value of nil.)
    googleDriveService.authorizer = googleAuthorizer.authorization
}
```
This is the scope I need for Google Drive to access just the files I create from my app.

When the user taps the button to export something to her Google Drive, I check whether authorization for this is already there:
```
GAuthorizer.shared.isAuthorized()
```

If this returns `true`, I know that the authorization is there AND I have already set the authorization entity that is the result of the authorization process in `googleDriveService`.

Otherwise, I make sure to set the final authorization callback function like so...
```
GAuthorizer.shared.authorizationCompletion = {
  (result: AuthorizationResult) in
  switch result {
  case .ok:
    googleDriveService.authorizer = GAuthorizer.shared.authorization
    // Log event, show alert, ...
  case .canceled:
    fallthrough
  case .failed:
    googleDriveService.authorizer = nil
    // Log event, show alert, ... 
}

// (AuthorizationResult is just this:)
enum AuthorizationResult {
  case ok, canceled, failed(reason: String)
}
```

..then initiate the authorization call from the view controller (`parentViewController` here) that I am in right now:
```
GAuthorizer.shared.authorize(in: parentViewController)
```

Setting `authorizationCompletion` has to be done only once, like the setup above. However, the completion references a view that may just not be there yet on app start. That's why this is not part of the general setup.

Finally, for the callback that comes in from the app-external authorization in Safari & Co, I just have to add in the AppDelegate.swift:
```
func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey:Any]) -> Bool {
  if GAuthorizer.shared.continueAuthorization(with: url) {
    return true
  }

 // (There will be other callback checks here for the likes of Dropbox etc...)
}
```

That's it. I hope I didn't forget anything. Ping me, if I have, please.

*To see things in action, you can download the [world's best stopwatch app for sports coaches, parents, and supporters](http://smartstopwatch.com) (or so the megalomaniacal app author claims) for free, time some athletes and tap 'Export' in the main Athletes view (enable one export option in the settings to do so).*
