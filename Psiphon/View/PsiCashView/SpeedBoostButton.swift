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

@objc final class SpeedBoostButton: GradientButton, Bindable {

    enum SpeedBoostButtonState: Equatable {
        case inactive
        case active(Date)
    }

    // Timer tick frequency.
    static let TickFrequency = TimeInterval(1.0)

    // UI starts showing the 'seconds' counter when expiry is less than or equal to `ShowSecondsAt`.
    static let ShowSecondsAt = TimeInterval(5 * 60)

    let formatter: DateComponentsFormatter
    let activeTint = UIColor.weirdGreen()

    var timer: Timer? = nil {
        willSet {
            if newValue == nil {
                self.timer?.invalidate()
            }
        }
    }

    var timerState: SpeedBoostButtonState? = .none {
        // Carries out the effect of setting a new timer state.
        willSet(newState) {
            switch newState {
            case .active(let newExpiry):
                // No-op if expiry hasn't changed.
                if case let .active(expiry) = self.timerState, expiry == newExpiry {
                    return
                }
                scheduleTimer(expiry: newExpiry)

            case .inactive:
                self.timer = nil
            case .none:
                fatalError("Invalid SpeedBoostButton state")
            }

            updateUIState(timerState: newState!)
        }
    }

    init() {
        formatter = DateComponentsFormatter()
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = .pad

        super.init(gradient: .blue)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func initViewBeforeShadowAndGradient() {
        let plusImage = UIImage(named: "PsiCash_InstantPurchaseButton")!.withRenderingMode(.alwaysTemplate)

        setImage(plusImage, for: .normal)
        setImage(plusImage, for: .highlighted)
        imageView!.contentMode = .scaleAspectFit

        // Adds space between image and label
        let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
        if isRTL {
            imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 10.0, bottom: 0.0, right: 0.0)
        } else {
            imageEdgeInsets = UIEdgeInsets(top: 0.0, left: 0.0, bottom: 0.0, right: 10.0)
        }

        titleLabel!.font = AvenirFont.demiBold.font(.h3)
    }

    func bind(_ newValue: SpeedBoostButtonState) {
        switch newValue {
        case .inactive:
            guard self.timerState != .inactive else {
                return
            }
            self.timerState = .inactive
        case .active(let expiry):
            guard expiry.timeIntervalSinceNow > 0 else {
                return
            }
            self.timerState = .active(expiry)
        }
    }

    // ObjC bridging function for `bind`.
    @objc func setExpiryTime(_ expiry: Date?) {
        if let expiry = expiry {
            self.bind(.active(expiry))
        } else {
            self.bind(.inactive)
        }
    }

    private func scheduleTimer(expiry: Date) {
        // No-op if timer is already active.
        guard self.timer == nil else {
            return
        }

        // Updates title text.
        updateTitle(expiry: expiry)

        self.timer = Timer.scheduledTimer(withTimeInterval: Self.TickFrequency, repeats: true)
        { [weak self] timer in
            guard let self = self else {
                timer.invalidate()
                return
            }

            // If state has changed to inactive, return immediately. (Timer already invalidated)
            guard case let .active(expiry) = self.timerState else {
                return
            }

            // If expiry date has passed, updates `timerState` to inactive. (Invalidates the timer)
            guard expiry.timeIntervalSinceNow > 0 else {
                self.timerState = .inactive
                return
            }

            // Updates UI.
            self.updateTitle(expiry: expiry)
        }
    }

    // MARK: UI Update methods
    private func updateTitle(expiry: Date) {
        if expiry.timeIntervalSinceNow <= Self.ShowSecondsAt {
            self.formatter.allowedUnits = [.minute, .second]
        } else {
            self.formatter.allowedUnits = [.hour, .minute]
        }

        let time = formatter.string(from: max(0.0, expiry.timeIntervalSinceNow))!
        let title = UserStrings.Speed_boost_active(time: time)

        setTitle(title, for: .normal)
        setTitle(title, for: .highlighted)
    }

    private func updateUIState(timerState: SpeedBoostButtonState) {
        switch timerState {
        case .active(_):
            layer.borderWidth = 2.0

            // Sets colors
            gradientColors = [UIColor.clear].cgColors
            layer.borderColor = activeTint.cgColor
            setTitleColor(activeTint, for: .normal)
            setTitleColor(activeTint, for: .highlighted)
            imageView!.tintColor = activeTint

        case .inactive:
            setTitle(UserStrings.Speed_boost(), for: .normal)
            setTitle(UserStrings.Speed_boost(), for: .highlighted)
            layer.borderWidth = 0.0

            // Resets colors
            gradientColors = Gradients.blue.colors
            setTitleColor(UIColor.white, for: .normal)
            setTitleColor(UIColor.white, for: .highlighted)
            imageView!.tintColor = UIColor.white
        }
    }

}
