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

import Foundation
import UIKit
import RxSwift

class PsiCashViewController: UIViewController {

    // Views
    let balanceView = PsiCashBalanceView(frame: CGRect.zero)
    let closeButton = CloseButton(frame: CGRect.zero)
    let tabControl = TabControlView(frame: CGRect.zero)

    // Injected Services
    let psiCash: Observable<PsiCashActorPublisher?>

    // TODO! remove thoughts
    // need to pass the registry.
    // The AppRoot is side-effecting. So needs IO
    // Business logic changes, so there's no need to couple actors together.
    //

    // TODO! this should be removed
    init(psiCash: Observable<PsiCashActorPublisher?>) {
        self.psiCash = psiCash
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Setup and add all the views here
    override func viewDidLoad() {
        setBackgroundGradient(for: view)

        balanceView.setAmount(nanoPsi: 0)

        // TODO! localize this
        tabControl.addControl(title: "Add PsiCash") {
            print("add psicash button")
        }

        tabControl.addControl(title: "Speed Boost") {
            print("speed boost button")
        }

        // Add subviews
        view.addSubview(balanceView)
        view.addSubview(closeButton)
        view.addSubview(tabControl)

        // Setup layout guide
        let viewLayoutGuide = addBackwardsCompatibleSafeAreaLayoutGuide(to: view)

        let paddedLayoutGuide = UILayoutGuide()
        view.addLayoutGuide(paddedLayoutGuide)

        NSLayoutConstraint.activate([
            paddedLayoutGuide.topAnchor.constraint(equalTo: viewLayoutGuide.topAnchor),
            paddedLayoutGuide.bottomAnchor.constraint(equalTo: viewLayoutGuide.bottomAnchor),
            paddedLayoutGuide.centerXAnchor.constraint(equalTo: viewLayoutGuide.centerXAnchor),
            paddedLayoutGuide.widthAnchor.constraint(equalTo: viewLayoutGuide.widthAnchor,
                                                     multiplier: 0.91)
        ])

        // Setup subview constraints
        setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView: view)

        NSLayoutConstraint.activate([
            balanceView.centerXAnchor.constraint(equalTo: paddedLayoutGuide.centerXAnchor),
            balanceView.topAnchor.constraint(equalTo: paddedLayoutGuide.topAnchor,
                                             constant: 30.0),
        ])

        NSLayoutConstraint.activate([
             closeButton.centerYAnchor.constraint(equalTo: balanceView.centerYAnchor),
             closeButton.trailingAnchor.constraint(equalTo: paddedLayoutGuide.trailingAnchor),
             closeButton.widthAnchor.constraint(equalToConstant: 30.0),
             closeButton.heightAnchor.constraint(equalTo: closeButton.widthAnchor)
         ])

        NSLayoutConstraint.activate([
            tabControl.topAnchor.constraint(equalTo: balanceView.topAnchor, constant: 50.0),
            tabControl.centerXAnchor.constraint(equalTo: paddedLayoutGuide.centerXAnchor),
            tabControl.widthAnchor.constraint(equalTo: paddedLayoutGuide.widthAnchor),
            tabControl.heightAnchor.constraint(equalToConstant: 44.0)
        ])

    }

}
