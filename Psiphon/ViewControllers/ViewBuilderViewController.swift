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
import PsiApi

/// A view controller that is only initialized with a  view builder.
final class ViewBuilderViewController<T: ViewBuilder>: ReactiveViewController {

    private let viewBuilder: T
    var bindable: T.BuildType?

    init(
        viewBuilder: T,
        modalPresentationStyle: UIModalPresentationStyle,
        onDismissed: @escaping () -> Void
    ) {
        self.viewBuilder = viewBuilder
        super.init(onDismissed: onDismissed)

        self.modalPresentationStyle = modalPresentationStyle
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootViewLayoutGuide = makeSafeAreaLayoutGuide(addToView: view)
        self.view.backgroundColor = .black(withAlpha: 0.4)

        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .darkBlue()
        containerView.layer.cornerRadius = Style.alertBoxStyle.cornerRadius
        containerView.layer.masksToBounds = true
        containerView.layer.borderColor = UIColor.lightishBlueTwo().cgColor
        containerView.layer.borderWidth = Style.alertBoxStyle.borderWidth

        view.addSubview(containerView)

        containerView.activateConstraints {
            $0.constraint(to: rootViewLayoutGuide, .centerX(), .centerY()) +
                $0.widthAnchor.constraint(toDimension: rootViewLayoutGuide.widthAnchor,
                                          ratio: 0.8,
                                          max: 400) +
                [
                    $0.heightAnchor.constraint(lessThanOrEqualTo: rootViewLayoutGuide.heightAnchor,
                                               multiplier: 0.8)
                ]
        }

        self.bindable = T.BuildType.build(with: viewBuilder, addTo: containerView)
    }

}
