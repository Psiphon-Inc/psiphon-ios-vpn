/*
 * Copyright (c) 2019, Psiphon Inc.
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

import UIKit
import ReactiveSwift

struct EitherView<A: ViewBuilder, B: ViewBuilder>: ViewBuilder {
    typealias BindingType = Either<A.BuildType.BindingType, B.BuildType.BindingType>

    let leftBuilder: A
    let rightBuilder: B

    enum EitherViewable: ViewWrapper {
        case left(A.BuildType)
        case right(B.BuildType)

        var view: UIView {
            switch self {
            case .left(let bindableView):
                return bindableView.view
            case .right(let bindableView):
                return bindableView.view
            }
        }
    }

    init(_ leftBuilder: A, _ rightBuilder: B) {
        self.leftBuilder = leftBuilder
        self.rightBuilder = rightBuilder
    }

    func build(_ container: UIView?) -> MutableBindableViewable<BindingType, EitherViewable> {
        guard let container = container else {
            fatalError("EitherView build `container` not passed in")
        }
        return .init(viewable: .none) { viewable -> ((BindingType) -> EitherViewable?) in
            return { newValue in
                let newViewable: EitherViewable?
                switch newValue {
                case .left(let value):
                    var bindableViewable: A.BuildType
                    switch viewable {
                    case .right(_), .none:
                        bindableViewable = A.BuildType.build(with: self.leftBuilder,
                                                             addTo: container)
                        newViewable = .left(bindableViewable)
                    case .left(let leftBindableViewable):
                        newViewable = viewable!
                        bindableViewable = leftBindableViewable
                    }
                    bindableViewable.bind(value)

                case .right(let value):
                    var bindableViewable: B.BuildType
                    switch viewable {
                    case .left(_), .none:
                        bindableViewable = B.BuildType.build(with: self.rightBuilder,
                                                             addTo: container)
                        newViewable = .right(bindableViewable)
                    case .right(let rightBindableViewable):
                        newViewable = viewable!
                        bindableViewable = rightBindableViewable
                    }
                    bindableViewable.bind(value)

                }
                return newViewable
            }
        }
    }

}
