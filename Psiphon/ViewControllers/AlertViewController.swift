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

final class AlertViewController<T: ViewBuilder>: UIViewController {

    private let viewBuilder: T
    var bindable: T.BuildType?

    init(viewBuilder: T) {
        self.viewBuilder = viewBuilder
        super.init(nibName: nil, bundle: nil)

        self.modalPresentationStyle = .overFullScreen
    }

    required init?(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let rootViewLayoutGuide = addSafeAreaLayoutGuide(to: view)
        self.view.backgroundColor = .black(withAlpha: 0.4)

        let containerView = UIView(frame: .zero)
        containerView.backgroundColor = .darkBlue()
        containerView.layer.cornerRadius = Style.alertBoxStyle.cornerRadius
        containerView.layer.masksToBounds = true
        containerView.layer.borderColor = UIColor.lightishBlueTwo().cgColor
        containerView.layer.borderWidth = Style.alertBoxStyle.borderWidth

        view.addSubview(containerView)

        containerView.activateConstraints {
            [
                $0.centerXAnchor.constraint(equalTo: rootViewLayoutGuide.centerXAnchor),
                $0.centerYAnchor.constraint(equalTo: rootViewLayoutGuide.centerYAnchor),
                $0.widthAnchor.constraint(lessThanOrEqualTo: rootViewLayoutGuide.widthAnchor,
                                          multiplier: 0.7),
                $0.heightAnchor.constraint(lessThanOrEqualTo: rootViewLayoutGuide.widthAnchor,
                                           multiplier: 0.8)
            ]
        }


        self.bindable = T.BuildType.build(with: viewBuilder, addTo: containerView)
    }

}
