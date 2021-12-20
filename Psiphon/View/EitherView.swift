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
import Utilities

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
        return MutableBindableViewable<BindingType, EitherViewable>(viewable: .none) { viewable -> ((BindingType) -> EitherViewable?) in
            return { (newValue: BindingType) in
                
                switch newValue {
                    
                case .left(let value):
                    
                    let binding: A.BuildType
                    
                    switch viewable {
                    case .right(_), .none:
                        binding = self.leftBuilder.buildView(addTo: container)
                    case .left(let leftBinding):
                        binding = leftBinding
                    }
                    
                    binding.bind(value)
                    
                    return .left(binding)

                case .right(let value):
                    
                    let binding: B.BuildType
                    
                    switch viewable {
                    case .left(_), .none:
                        binding = self.rightBuilder.buildView(addTo: container)
                    case .right(let rightBinding):
                        binding = rightBinding
                    }
                    
                    binding.bind(value)
                    
                    return .right(binding)

                }
                
            }
        }
    }

}

/// `PlaceHolderView` is useful in an `EitherView` to be a placeholder for a view
/// that contains state that should not be lost (e.g. `WKWebView`).
/// Note that `EitherView`'s `bind(_:)` function rebuilds the view if it's value has changed.
struct PlaceholderView<PlaceholderType: UIView>: ViewBuilder {
    
    func build(_ container: UIView?) -> ImmutableBindableViewable<PlaceholderType, UIView> {

        let background = UIView(frame: .zero)
        background.backgroundColor = .darkGray2()
        
        return .init(viewable: background) { background in
            
            return { materializedView in
                
                background.subviews.forEach { $0.removeFromSuperview() }
                background.addSubview(materializedView)
                materializedView.activateConstraints {
                    $0.matchParentConstraints()
                }
                
            }
            
        }
        
    }
    
}
