/*
 * Copyright (c) 2020, Psiphon Inc.
 * All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 *
 */

import Foundation
import UIKit
import ReactiveSwift

public enum ViewControllerLifeCycle {
    case initing
    case viewDidLoad
    case viewWillAppear(animated: Bool)
    case viewDidAppear(animated: Bool)
    case viewWillDisappear(animated: Bool)
    case viewDidDisappear(animated: Bool)
}

extension ViewControllerLifeCycle {

    public var initing: Bool {
        guard case .initing = self else {
            return false
        }
        return true
    }

    public var viewDidLoad: Bool {
        guard case .viewDidLoad = self else {
            return false
        }
        return true
    }

    public var viewWillAppear: Bool {
        guard case .viewWillAppear = self else {
            return false
        }
        return true
    }

    public var viewDidAppear: Bool {
        guard case .viewDidAppear(_) = self else {
            return false
        }
        return true
    }

    public var viewWillDisappear: Bool {
        guard case .viewWillDisappear(_) = self else {
            return false
        }
        return true
    }

    public var viewDidDisappear: Bool {
        guard case .viewDidDisappear(_) = self else {
            return false
        }
        return true
    }

}

/// ReactiveViewController makes the values of UIViewController lifecycle calls available in a stream
/// and also buffers the last value.
open class ReactiveViewController: UIViewController {

    /// Value of the last UIViewController lifecycle call. The property wrapper provides
    /// an interface to obtain a stream of UIViewController lifecycle call values, which starts
    /// with the current value of this variable.
    @State public var lifeCycle: ViewControllerLifeCycle = .initing

    open override func viewDidLoad() {
        super.viewDidLoad()
        lifeCycle = .viewDidLoad
    }
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        lifeCycle = .viewWillAppear(animated: animated)
    }
    open override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        lifeCycle = .viewDidAppear(animated: animated)
    }

    open override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        lifeCycle = .viewWillDisappear(animated: animated)
    }

    open override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        lifeCycle = .viewDidDisappear(animated: animated)
    }

    public func presentOnViewDidAppear(_ viewControllerToPresent: UIViewController,
                                              animated flag: Bool,
                                              completion: (() -> Void)? = nil) {

        self.$lifeCycle.signalProducer
            .filter{ $0.viewDidAppear}.take(last: 1).startWithValues { [unowned self] _ in
                self.present(viewControllerToPresent, animated: flag, completion: completion)
        }
    }

}
