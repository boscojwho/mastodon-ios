//
//  AdaptiveStatusBarStyleNavigationController.swift
//  
//
//  Created by MainasuK Cirno on 2021-2-26.
//

import UIKit

// Make status bar style adptive for child view controller
// SeeAlso: `modalPresentationCapturesStatusBarAppearance`
final class AdaptiveStatusBarStyleNavigationController: UINavigationController {
    override var childForStatusBarStyle: UIViewController? {
        return visibleViewController
    }
}
