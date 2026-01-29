//
//  AppDelegate.swift
//  Mile A Day
//
//  Created by AI on 1/28/26.
//

import UIKit

class AppDelegate: NSObject, UIApplicationDelegate {
    
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        // Force the app to stay in portrait only
        return .portrait
    }
}

