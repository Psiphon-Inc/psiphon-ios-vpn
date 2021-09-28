/*
 * Copyright (c) 2021, Psiphon Inc.
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

/// A ViewWrapper that wraps a container UIView and builds it's content with the given view builder `A`.
struct ViewBuilderContainerView<A: ViewBuilder>: ViewWrapper, Bindable {
    
    typealias BindingType = A.BuildType.BindingType
    
    // Container view
    let view = UIView(frame: .zero)
    
    // Bindable object
    private let bindable : A.BuildType
    
    init(_ viewBuilder: A) {
        bindable = viewBuilder.build(view)
    }
    
    func bind(_ newValue: A.BuildType.BindingType) {
        bindable.bind(newValue)
    }
    
}
