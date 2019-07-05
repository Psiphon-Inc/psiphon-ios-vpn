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

enum SpeedBoostButtonStatus {
    case normal
    case active(TimeInterval)
}

@objc class SpeedBoostButton: GradientButton {

    let formatter: DateComponentsFormatter
    let activeTint = UIColor.weirdGreen()

    var status: SpeedBoostButtonStatus = .normal {
        didSet {
            switch status {
            case .normal:
                deactivateSpeedBoost()
            case .active(let timeInterval):
                activateSpeedBoost(displayTime: timeInterval)
            }
        }
    }

    override init(frame: CGRect) {
        formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad

        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initSequence() {
        let plusImage = UIImage(named: "PsiCash_InstantPurchaseButton")!.withRenderingMode(.alwaysTemplate)

        setImage(plusImage, for: .normal)
        setImage(plusImage, for: .highlighted)
        imageView!.contentMode = .scaleAspectFit

        // Adds space between image and label
        imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 10.0)

        // Initial `normal` state.
        deactivateSpeedBoost()

        titleLabel!.font = AvenirFont.demiBold.font(16.0)
    }

    // TODO! localize string
    private func activateSpeedBoost(displayTime: TimeInterval) {

        let time = formatter.string(from: displayTime)!
        let title = "Speed Boost Active: \(time)"

        setTitle(title, for: .normal)
        setTitle(title, for: .highlighted)

        layer.borderWidth = 2.0

        // Sets colors
        gradientColors = [UIColor.clear].cgColors
        layer.borderColor = activeTint.cgColor
        setTitleColor(activeTint, for: .normal)
        setTitleColor(activeTint, for: .highlighted)
        imageView!.tintColor = activeTint
    }

    // TODO! localize string
    private func deactivateSpeedBoost() {
        setTitle("Speed Boost", for: .normal)
        setTitle("Speed Boost", for: .highlighted)

        layer.borderWidth = 0.0

        // Resets colors
        gradientColors = defaultGradientColors
        setTitleColor(UIColor.white, for: .normal)
        setTitleColor(UIColor.white, for: .highlighted)
        imageView!.tintColor = UIColor.white
    }

}
