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

protocol UICases: Hashable, CaseIterable, CustomStringConvertible {}

/// Represents global app styles.
struct AppStyle {
    lazy var alertBoxStyle = Styling(borderWidth: 3.0)
    lazy var `default` = Styling()
}

struct Styling {
    var borderWidth: CGFloat = 5.0
    var cornerRadius: CGFloat = 8.0
    var padding: CGFloat = 15.0
    var largeButtonHeight: CGFloat = 60.0
    var statusBarStyle = UIStatusBarStyle.lightContent
    var buttonContentEdgeInsets = UIEdgeInsets(top: 10.0, left: 15.0, bottom: 10.0, right: 15.0)
}

enum Gradients: Int {
    case grey
    case blue

    var colors: [CGColor] {
        switch self {
        case .grey:
            return [.white, .softGrey1()].cgColors
        case .blue:
            return [UIColor.lightishBlue(), UIColor.lightRoyalBlueTwo()].cgColors
        }
    }
}

enum FontSize: Float {
    case h1 = 26.0
    case h3 = 16.0
    case normal = 14.0
}

enum AvenirFont: String {
    case medium = "AvenirNext-Medium"
    case demiBold = "AvenirNext-DemiBold"
    case bold = "AvenirNext-Bold"

    func font(_ size: FontSize = .normal) -> UIFont {
        return UIFont(name: self.rawValue, size: CGFloat(size.rawValue))!
    }
    
    /// Prefer to use `font(_:)` instead for better consistency across the app.
    func customFont(_ size: Float) -> UIFont {
        return UIFont(name: self.rawValue, size: CGFloat(size))!
    }
}

enum Loading<Value: Equatable>: Equatable {
    case loading
    case loaded(Value)
}

extension UILabel {

    static func make(
        text: String = "",
        fontSize: FontSize = .normal,
        typeface: AvenirFont = .demiBold,
        color: UIColor = .white,
        numberOfLines: Int = 1,
        alignment: NSTextAlignment = .natural) -> UILabel {

        let v = UILabel(frame: .zero)
        v.backgroundColor = .clear
        v.adjustsFontSizeToFitWidth = true
        v.minimumScaleFactor = 0.6
        v.font = typeface.font(fontSize)
        v.textAlignment = alignment
        v.textColor = color
        v.isUserInteractionEnabled = false
        v.clipsToBounds = false
        v.text = text

        v.numberOfLines = numberOfLines
        if numberOfLines == 0 {
            v.lineBreakMode = .byWordWrapping
        }

        return v
    }

}

enum EdgeInsets {
    case normal

    var value: UIEdgeInsets {
        switch self {
        case .normal:
            return .init(top: Style.default.padding, left: Style.default.padding,
                         bottom: Style.default.padding, right: Style.default.padding)
        }
    }
}

extension UIButton {

    func contentEdgeInset(_ inset: EdgeInsets) {
        self.contentEdgeInsets = inset.value
    }

}

extension UIImageView {

    static func make(image: String,
                     contentMode: UIView.ContentMode = .scaleAspectFit) -> UIImageView {
        let v = UIImageView(image: UIImage(named: image))
        v.contentMode = contentMode
        return v
    }

}

extension UITableViewCell {
    /// Returns true if the cells `contentView` has any subviews.
    /// Indiciating that the cell has some content.
    var hasContent: Bool {
        return contentView.subviews.count > 0
    }
}

/// Sets `translatesAutoresizingMaskIntoConstraints` to false for each child of given view.
func setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView view: UIView) {
    view.subviews.forEach {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
}


/// Backwards compatible safe area layout guide.
func addSafeAreaLayoutGuide(to view: UIView) -> UILayoutGuide {
    let layoutGuide = UILayoutGuide()
    view.addLayoutGuide(layoutGuide)

    if #available(iOS 11.0, *) {
        NSLayoutConstraint.activate([
            layoutGuide.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            layoutGuide.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            layoutGuide.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            layoutGuide.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
        ])

    } else {
        // Fallback on earlier versions
        NSLayoutConstraint.activate([
            layoutGuide.topAnchor.constraint(equalTo: view.topAnchor),
            layoutGuide.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            layoutGuide.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            layoutGuide.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    return layoutGuide
}


func addShadow(toLayer layer: CALayer?) {
    guard let layer = layer else {
        return
    }

    guard !(layer is CATransformLayer) else {
        fatalErrorFeedbackLog("Cannot add shadow to CATransformLayer")
    }

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = CGSize(width: 0.0, height: 1.0)
    layer.shadowOpacity = 0.22
    layer.shadowRadius = 2.0
}

/// Should set frame on returned `CAGradientLayer` and set path on returned `CAShapeLayer`.
func makeGradientBorderLayer(colors: [CGColor], width: CGFloat = 2.0)
    -> (CAGradientLayer, CAShapeLayer) {
    let gradient = CAGradientLayer()
    gradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    gradient.endPoint = CGPoint(x: 0.5, y: 1.0)
    gradient.colors = colors

    let borderMask = CAShapeLayer()
    borderMask.lineWidth = width
    borderMask.fillColor = nil
    borderMask.strokeColor = UIColor.black.cgColor
    gradient.mask = borderMask

    return (gradient, borderMask)
}


func setBackgroundGradient(for view: UIView) {
    guard view.bounds.size != CGSize.zero else {
        preconditionFailureFeedbackLog("view bounds not set")
    }

    let backgroundGradient = CAGradientLayer()
    backgroundGradient.colors = [UIColor.lightNavy().cgColor,
                                 UIColor.darkNavy().cgColor]

    backgroundGradient.frame = view.bounds
    backgroundGradient.startPoint = CGPoint(x: 0.5, y: 0.0)
    backgroundGradient.endPoint = CGPoint(x: 0.5, y: 0.33)

    view.layer.insertSublayer(backgroundGradient, at: 0)
}

// MARK: AutoLayout

enum Anchor {
    case top(Float = 0)
    case leading(Float = 0)
    case trailing(Float = 0)
    case bottom(Float = 0)
    case centerX(Float = 0)
    case centerY(Float = 0)
    case width(Float = 0)
    case height(Float = 0)
}

protocol Anchorable {
    var leadingAnchor: NSLayoutXAxisAnchor { get }

    var trailingAnchor: NSLayoutXAxisAnchor { get }

    var leftAnchor: NSLayoutXAxisAnchor { get }

    var rightAnchor: NSLayoutXAxisAnchor { get }

    var topAnchor: NSLayoutYAxisAnchor { get }

    var bottomAnchor: NSLayoutYAxisAnchor { get }

    var widthAnchor: NSLayoutDimension { get }

    var heightAnchor: NSLayoutDimension { get }

    var centerXAnchor: NSLayoutXAxisAnchor { get }

    var centerYAnchor: NSLayoutYAxisAnchor { get }

}

extension Anchorable {

    func constraint(to anchorable: Anchorable,
                    _ anchors: Anchor...) -> [NSLayoutConstraint] {
        constraint(to: anchorable, anchors)
    }

    func constraint(to anchorable: Anchorable,
                    _ anchors: [Anchor]) -> [NSLayoutConstraint] {
        var constraints = [NSLayoutConstraint]()
        for anchor in anchors {
            switch anchor {
            case .top(let const):
                constraints.append(
                    self.topAnchor.constraint(equalTo: anchorable.topAnchor,
                                              constant: CGFloat(const)))
            case .leading(let const):
                constraints.append(
                    self.leadingAnchor.constraint(equalTo: anchorable.leadingAnchor,
                                                  constant: CGFloat(const)))
            case .trailing(let const):
                constraints.append(
                    self.trailingAnchor.constraint(equalTo: anchorable.trailingAnchor,
                                                   constant: CGFloat(const)))
            case .bottom(let const):
                constraints.append(
                    self.bottomAnchor.constraint(equalTo: anchorable.bottomAnchor,
                                                 constant: CGFloat(const)))
            case .centerX(let const):
                constraints.append(
                    self.centerXAnchor.constraint(equalTo: anchorable.centerXAnchor,
                                                  constant: CGFloat(const)))
            case .centerY(let const):
                constraints.append(
                    self.centerYAnchor.constraint(equalTo: anchorable.centerYAnchor,
                                                  constant: CGFloat(const)))
            case .width(let const):
                constraints.append(
                    self.widthAnchor.constraint(equalTo: anchorable.widthAnchor,
                                                constant: CGFloat(const)))
            case .height(let const):
                constraints.append(
                    self.heightAnchor.constraint(equalTo: anchorable.heightAnchor,
                                                 constant: CGFloat(const)))
            }
        }
        return constraints
    }

}

extension UILayoutGuide: Anchorable {

    func activateConstraints(_ constraintsBuilder: (UILayoutGuide) -> [NSLayoutConstraint]) {
        NSLayoutConstraint.activate(constraintsBuilder(self))
    }

}

extension UIView: Anchorable {

    func activateConstraints(_ constraintsBuilder: (UIView) -> [NSLayoutConstraint]) {
        self.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate(constraintsBuilder(self))
    }

}

extension UIView {

    func constraintToParent(_ anchors: Anchor...) -> [NSLayoutConstraint] {
        guard let parent = self.superview else {
            fatalErrorFeedbackLog("'constraintToParent' requires the view to have a parent view")
        }
        return constraint(to: parent, anchors)
    }

    func matchParentConstraints(top: Float = 0, leading: Float = 0, trailing: Float = 0,
                                bottom: Float = 0) -> [NSLayoutConstraint] {
        return self.constraintToParent(.top(top), .leading(leading),
                                       .trailing(trailing), .bottom(bottom))
    }

    func contentHuggingPriority(lowerThan view: UIView, for axis: NSLayoutConstraint.Axis) {
        self.setContentHuggingPriority(view.contentHuggingPriority(for: axis) - 1, for: axis)
    }

    func widthConstraint(to normal: CGFloat, withMax max: CGFloat) -> [NSLayoutConstraint] {
        let max = self.widthAnchor.constraint(lessThanOrEqualToConstant: max)
        max.priority = .required
        max.isActive = true

        let normal = self.widthAnchor.constraint(equalToConstant: normal)
        normal.priority = .defaultHigh
        normal.isActive = true
        return [max, normal]
    }

    func heightConstraint(to normal: CGFloat, withMax max: CGFloat) -> [NSLayoutConstraint] {
        let max = self.heightAnchor.constraint(lessThanOrEqualToConstant: max)
        max.priority = .required
        max.isActive = true

        let normal = self.heightAnchor.constraint(equalToConstant: normal)
        normal.priority = .defaultHigh
        normal.isActive = true
        return [max, normal]
    }

}

extension NSLayoutConstraint {

    func priority(_ value: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = value
        return self
    }

    func priority(_ value: Int) -> NSLayoutConstraint {
        return self.priority(UILayoutPriority(rawValue: Float(value)))
    }

    func priority(higherThan constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        guard constraint.priority < UILayoutPriority.required else {
            fatalErrorFeedbackLog("Priority cannot be higher than 'required'")
        }
        self.priority = constraint.priority + 1
        return self
    }

    func priority(lowerThan constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        guard constraint.priority.rawValue > 0 else {
            fatalErrorFeedbackLog("Priority cannot be lower than 0")
        }
        self.priority = constraint.priority - 1
        return self
    }

}

// MARK: -

extension UIView {

    func addSubviews(_ subviews: UIView...) {
        subviews.forEach {
            self.addSubview($0)
        }
    }

}

extension Array where Element == UIColor {

    var cgColors: [CGColor] {
        return self.map { $0.cgColor }
    }

}

class WrappedNumberFormatter: NumberFormatter {

    func string(from value: Double) -> String? {
        return self.string(from: NSNumber(value: value))
    }

}

final class CurrencyFormatter: WrappedNumberFormatter {

    init(locale: Locale) {
        super.init()
        self.locale = locale
        self.formatterBehavior = .behavior10_4
        self.numberStyle = .currency
    }

    required init?(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
    }

}

final class PsiCashAmountFormatter: WrappedNumberFormatter {

    init(locale: Locale) {
        super.init()
        self.locale = locale
        self.numberStyle = .decimal
        self.formatterBehavior = .behavior10_4
    }

    required init?(coder: NSCoder) {
        fatalErrorFeedbackLog("init(coder:) has not been implemented")
    }

}

// MARK: Colour

extension UIColor {

    static func black(withAlpha value: Float) -> UIColor {
        return .init(white: 0.0, alpha: CGFloat(value))
    }

    static func white(withAlpha value: Float) -> UIColor {
        return .init(white: 1.0, alpha: CGFloat(value))
    }

}

// MARK: Composable views

protocol BindableViewable: class, Bindable, ViewWrapper {
    associatedtype WrappedView: ViewWrapper

    static func build<Builder>(with builder: Builder, addTo container: UIView) -> Builder.BuildType where Builder: ViewBuilder, Builder.BuildType == Self
}

/// A ViewBuilder is a type which has all necessary information to build a `BindableView`.
protocol ViewBuilder {
    associatedtype BuildType: BindableViewable

    /// Builds a `BindableViewable`. In current implementation the `BindableViewable`
    /// is either a `StrictBindableViewable` or a `MutableBindableViewable`.
    ///
    /// - A `StrictBindableViewable` should ignore the `container` parameter, and never rely on it.
    /// This value may or may not be nil, depending on whether the `container` is being re-used.
    ///
    /// - A `MutableBindableViewable` should add it's views to the passed in `container`.
    /// In this case the passed in `container` will alwayb be non-nil.
    func build(_ container: UIView?) -> BuildType
}

/// A type that wraps a `UIView` object.
/// - Note:`UIView` itslef conforms to Viewable.
protocol ViewWrapper {
    var view: UIView { get }
}

extension UIView: ViewWrapper {
    var view: UIView { self }
}

final class StrictBindableViewable<BindingType: Equatable, WrappedView: ViewWrapper>: BindableViewable {
    typealias WrappedView = WrappedView
    typealias BindingType = BindingType

    var view: UIView { viewable.view }

    let viewable: WrappedView
    let binding: (BindingType) -> Void

    init(viewable: WrappedView, _ bindingWrapper: (WrappedView) -> ((BindingType) -> Void)) {
        self.viewable = viewable
        self.binding = bindingWrapper(viewable)
    }

    func bind(_ newValue: BindingType) {
        binding(newValue)
    }

    /// Nil is passed to `builder`s `build`  function, as this ViewBuilder type doesn't allow mutating the cotainer.
    /// TODO: This nil passing shows that this is not a good abstraction.
    static func build<Builder: ViewBuilder>(
        with builder: Builder, addTo container: UIView
    ) -> Builder.BuildType where BindingType == Builder.BuildType.BindingType {

        // Cleans up the container.
        container.subviews.forEach { $0.removeFromSuperview() }

        let bindableViewable = builder.build(nil)
        container.addSubview(bindableViewable.view)
        bindableViewable.view.activateConstraints { $0.matchParentConstraints() }
        return bindableViewable
    }
}

/// Wraps a `Viewable` that can be mutated.
final class MutableBindableViewable<BindingType: Equatable, WrappedView: ViewWrapper>: BindableViewable {
    typealias WrappedView = WrappedView
    typealias BindingType = BindingType

    var view: UIView { viewable!.view }

    private var viewable: WrappedView?
    private let bindingWrapper: (WrappedView?) -> ((BindingType) -> WrappedView?)

    init(viewable: WrappedView?,
         _ bindingWrapper: @escaping (WrappedView?) -> ((BindingType) -> WrappedView?)) {
        self.viewable = viewable
        self.bindingWrapper = bindingWrapper
    }

    func bind(_ newValue: BindingType) {
        viewable = bindingWrapper(viewable)(newValue)
    }

    // Calls the `builder` build function with the passed in `container`.
    static func build<Builder: ViewBuilder>(
        with builder: Builder, addTo container: UIView
    ) -> Builder.BuildType where MutableBindableViewable == Builder.BuildType {
        container.subviews.forEach { $0.removeFromSuperview() }
        return builder.build(container)
    }

}
