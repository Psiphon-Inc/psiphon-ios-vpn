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
import class PsiApi.ReactiveViewController
import struct PsiApi.Event

/// Represents global app styles.
struct AppStyle {
    lazy var alertBoxStyle = Styling(borderWidth: 3.0)
    lazy var `default` = Styling()
}

struct Styling {
    
    /// No layout should be larger in width than this constant.
    var layoutMaxWidth: CGFloat = 700.0
    var layoutWidthToHeightRatio: Float = 0.91
    
    var animationDuration: TimeInterval = 0.1
    var borderWidth: CGFloat = 5.0
    var cornerRadius: CGFloat = 8.0
    var padding: CGFloat = 15.0
    var largePadding: CGFloat = 20.0

    /// Offset for negative space at the bottom of screen.
    /// This is useful for scroll views, where last items might
    /// be too close to the bottom edge of the screen.
    var screenBottomOffset: CGFloat = 40.0

    var buttonHeight: CGFloat = 44.0
    var largeButtonHeight: CGFloat = 60.0
    var statusBarStyle = UIStatusBarStyle.lightContent
    var buttonContentEdgeInsets = UIEdgeInsets(top: 10.0, left: 15.0, bottom: 10.0, right: 15.0)
    var buttonMinimumContentEdgeInsets = UIEdgeInsets(top: 5.0, left: 5.0, bottom: 5.0, right: 5.0)
    
    var disabledButtonAlpha = 0.7
    
    var defaultBackgroundColor = UIColor.darkBlue()
    
}

enum Gradients: Int {
    
    case grey
    case blue
    case vividBlue

    var colors: [CGColor] {
        switch self {
        case .grey:
            return [.white, .softGrey1()].cgColors
        case .blue:
            return [UIColor.lightishBlue(), UIColor.lightRoyalBlueTwo()].cgColors
        case .vividBlue:
            return [UIColor.lightishBlue(), UIColor.vividBlue()].cgColors
        }
    }
}

enum FontSize: Float {
    
    /// 26-pt font size.
    case h1 = 26.0
    
    /// 18-pt font size.
    case h2 = 18.0
    
    /// 16-pt font size.
    case h3 = 16.0
    
    /// 14-pt font size.
    case normal = 14.0
    
    /// 12-pt font size.
    case subtitle = 12.0
    
}

enum AvenirFont: String {
    case medium = "AvenirNext-Medium"
    case demiBold = "AvenirNext-DemiBold"
    case bold = "AvenirNext-Bold"
    case mediumItalic = "AvenirNext-MediumItalic"

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

/// Applies `applyMutation` function to each of the `values` in order.
func mutate<Ref: AnyObject>(_ values: Ref..., applyMutations: (Ref) -> Void) {
    for value in values {
        applyMutations(value)
    }
}

/// Applies `applyMutation` function to each of the `values` in order.
func mutate<Ref: AnyObject>(_ values: [Ref], applyMutations: (Ref) -> Void) {
    for value in values {
        applyMutations(value)
    }
}

struct Padding: Equatable {
    
    let top: Float
    let bottom: Float
    let leading: Float
    let trailing: Float
    
    init(
        top: Float = 0,
        bottom: Float = 0,
        leading: Float = 0,
        trailing: Float = 0
    ) {
        self.top = top
        self.bottom = bottom
        self.leading = leading
        self.trailing = trailing
    }
    
}

extension UILabel {

    static func make<LabelView: UILabel>(
        text: String = "",
        fontSize: FontSize = .normal,
        typeface: AvenirFont = .demiBold,
        color: UIColor = .white,
        numberOfLines: Int = 1,
        alignment: NSTextAlignment = .natural) -> LabelView {

        let label = LabelView(frame: .zero)
        label.apply(text: text,
                    fontSize: fontSize,
                    typeface: typeface,
                    color: color,
                    numberOfLines: numberOfLines,
                    alignment: alignment)
        return label
    }
    
    func apply(
        text: String = "",
        fontSize: FontSize = .normal,
        typeface: AvenirFont = .demiBold,
        color: UIColor = .white,
        numberOfLines: Int = 1,
        alignment: NSTextAlignment = .natural
    ) {
        backgroundColor = .clear
        adjustsFontSizeToFitWidth = true
        minimumScaleFactor = 0.6
        font = typeface.font(fontSize)
        textAlignment = alignment
        textColor = color
        clipsToBounds = false
        self.text = text
        
        self.numberOfLines = numberOfLines
        if numberOfLines == 0 {
            lineBreakMode = .byWordWrapping
        }
    }

}

extension UIStackView {
    
    static func make(
        axis: NSLayoutConstraint.Axis = .horizontal,
        distribution: UIStackView.Distribution = .fill,
        alignment: UIStackView.Alignment = .fill,
        spacing: CGFloat = 0,
        margins: (top: CGFloat, bottom: CGFloat)? = nil
    ) -> UIStackView {
        let v = UIStackView(frame: .zero)
        mutate(v) {
            $0.axis = axis
            $0.distribution = distribution
            $0.alignment = alignment
            $0.spacing = spacing
            
            if let margins = margins {
                $0.isLayoutMarginsRelativeArrangement = true
                if #available(iOS 11.0, *) {
                    $0.directionalLayoutMargins = .init(top: margins.top, leading: 0.0,
                                                        bottom: margins.bottom, trailing: 0)
                } else {
                    $0.layoutMargins = .init(top: margins.top, left: 0.0,
                                             bottom: margins.bottom, right: 0)
                }
            }
            
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
    
    func setContentEdgeInsets(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        switch UIApplication.shared.userInterfaceLayoutDirection {
        case .leftToRight:
            self.contentEdgeInsets = UIEdgeInsets(top: top, left: leading, bottom: bottom, right: trailing)
        case .rightToLeft:
            self.contentEdgeInsets = UIEdgeInsets(top: top, left: trailing, bottom: bottom, right: leading)
        @unknown default:
            fatalError()
        }
    }

}

extension UIImageView {

    static func make(
        image imageName: String? = nil,
        contentMode: UIView.ContentMode = .scaleAspectFit,
        easyToShrink: Bool = false
    ) -> UIImageView {
        let v = UIImageView(frame: .zero)
        
        if let imageName = imageName {
            v.image = UIImage(named: imageName)
        }
        
        v.contentMode = contentMode
        
        if easyToShrink {
            v.setContentCompressionResistancePriority(
                (.defaultHigh - 1, .vertical),
                (.defaultHigh - 1, .horizontal)
            )
        }
        
        return v
    }

}

extension UITableViewCell {
    /// Returns true if the cells `contentView` has any subviews.
    /// Indicating that the cell has some content.
    var hasContent: Bool {
        return contentView.subviews.count > 0
    }
}

extension UIStackView {
    
    func addArrangedSubviews(_ subviews: UIView...) {
        for view in subviews {
            self.addArrangedSubview(view)
        }
    }
    
}

/// Sets `translatesAutoresizingMaskIntoConstraints` to false for each child of given view.
func setChildrenAutoresizingMaskIntoConstraintsFlagToFalse(forView view: UIView) {
    view.subviews.forEach {
        $0.translatesAutoresizingMaskIntoConstraints = false
    }
}


/// Backwards compatible safe area layout guide.
func makeSafeAreaLayoutGuide(addToView view: UIView) -> UILayoutGuide {
    let layoutGuide = UILayoutGuide()
    view.addLayoutGuide(layoutGuide)
    layoutGuide.activateConstraints {
        $0.constraint(to: view.safeAreaAnchors, [.top(), .bottom(), .leading(), .trailing()])
    }
    return layoutGuide
}


func addShadow(toLayer layer: CALayer?) {
    guard let layer = layer else {
        return
    }

    guard !(layer is CATransformLayer) else {
        fatalError("Cannot add shadow to CATransformLayer")
    }

    layer.shadowColor = UIColor.black.cgColor
    layer.shadowOffset = CGSize(width: 0.0, height: 2.0)
    layer.shadowOpacity = 0.3
    layer.shadowRadius = 2.0
    layer.masksToBounds = false
}


func setBackgroundGradient(for view: UIView) {
    guard view.bounds.size != CGSize.zero else {
        fatalError("view bounds not set")
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

extension UILayoutPriority {
    
    /// Priority value of `UILayoutPriority.requied - 1` (i.e. 999)
    static let belowRequired = UILayoutPriority(999)
    
}

enum Anchor {
    case top(Float = 0.0, UILayoutPriority = .required)
    case leading(Float = 0.0, UILayoutPriority = .required)
    case trailing(Float = 0.0, UILayoutPriority = .required)
    case bottom(Float = 0.0, UILayoutPriority = .required)
    case centerX(Float = 0.0, UILayoutPriority = .required)
    case centerY(Float = 0.0, UILayoutPriority = .required)
    case width(const: Float = 0.0, multiplier: Float = 1.0, UILayoutPriority = .required)
    case height(const: Float = 0.0, multiplier: Float = 1.0, UILayoutPriority = .required)
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

extension NSLayoutDimension {
    
    func constraint(default: CGFloat, max: CGFloat? = nil) -> [NSLayoutConstraint] {
        let defaultConstraint = self.constraint(equalToConstant: `default`)
            .priority(.defaultHigh)
        
        if let max = max {
            let maxConstraint = self.constraint(lessThanOrEqualToConstant: max)
                .priority(.required)
            
            return [maxConstraint, defaultConstraint]
            
        } else {
            return [defaultConstraint]
        }
    }
    
    func constraint(
        toDimension dimension: NSLayoutDimension, ratio: Float = 1.0, max maybeMax: CGFloat? = nil
    ) -> [NSLayoutConstraint] {
        
        var constraints = [
            self.constraint(equalTo: dimension, multiplier: CGFloat(ratio))
                .priority(.belowRequired),
        ]
        
        if let max = maybeMax {
            constraints.append(
                self.constraint(lessThanOrEqualToConstant: max).priority(.required)
            )
        }
        
        return constraints
    }
    
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
            case let .top(const, priority):
                constraints.append(
                    self.topAnchor.constraint(
                        equalTo: anchorable.topAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )
            case let .leading(const, priority):
                constraints.append(
                    self.leadingAnchor.constraint(
                        equalTo: anchorable.leadingAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )
                
            case let .trailing(const, priority):
                constraints.append(
                    self.trailingAnchor.constraint(
                        equalTo: anchorable.trailingAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )

            case let .bottom(const, priority):
                constraints.append(
                    self.bottomAnchor.constraint(
                        equalTo: anchorable.bottomAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )

            case let .centerX(const, priority):
                constraints.append(
                    self.centerXAnchor.constraint(
                        equalTo: anchorable.centerXAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )
                
            case let .centerY(const, priority):
                constraints.append(
                    self.centerYAnchor.constraint(
                        equalTo: anchorable.centerYAnchor,
                        constant: CGFloat(const)
                    ).priority(priority)
                )
                
            case let .width(const: const, multiplier: multiplier, priority):
                constraints.append(
                    self.widthAnchor.constraint(
                        equalTo: anchorable.widthAnchor,
                        multiplier: CGFloat(multiplier),
                        constant: CGFloat(const)
                    ).priority(priority)
                )
                
            case let .height(const: const, multiplier: multiplier, priority):
                constraints.append(
                    self.heightAnchor.constraint(
                        equalTo: anchorable.heightAnchor,
                        multiplier: CGFloat(multiplier),
                        constant: CGFloat(const)
                    ).priority(priority)
                )
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
    
    var safeAreaAnchors: Anchorable {
        if #available(iOS 11.0, *) {
            return self.safeAreaLayoutGuide
        } else {
            return self
        }
    }

    func constraintToParent(_ anchors: Anchor...) -> [NSLayoutConstraint] {
        guard let parent = self.superview else {
            fatalError("'constraintToParent' requires the view to have a parent view")
        }
        return constraint(to: parent, anchors)
    }
    
    func constraintToParentSafeArea(_ anchors: Anchor...) -> [NSLayoutConstraint] {
        guard let parent = self.superview else {
            fatalError("'constraintToParent' requires the view to have a parent view")
        }
        return constraint(to: parent.safeAreaAnchors, anchors)
    }

    func matchParentConstraints(top: Float = 0, leading: Float = 0, trailing: Float = 0,
                                bottom: Float = 0) -> [NSLayoutConstraint] {
        return self.constraintToParent(.top(top), .leading(leading),
                                       .trailing(trailing), .bottom(bottom))
    }

    func setContentHuggingPriority(lowerThan view: UIView, for axis: NSLayoutConstraint.Axis) {
        self.setContentHuggingPriority(view.contentHuggingPriority(for: axis) - 1, for: axis)
    }
    
    func setContentHuggingPriority(higherThan view: UIView, for axis: NSLayoutConstraint.Axis) {
        self.setContentHuggingPriority(view.contentHuggingPriority(for: axis) + 1, for: axis)
    }
    
    func setContentHuggingPriority(
        _ values: (priority: UILayoutPriority, axis: NSLayoutConstraint.Axis)...
    ) {
        for (priority, axis) in values {
            self.setContentHuggingPriority(priority, for: axis)
        }
    }
    
    open func setContentCompressionResistancePriority(
        _ values: (priority: UILayoutPriority, axis: NSLayoutConstraint.Axis)...
    ) {
        for (priority, axis) in values {
            self.setContentCompressionResistancePriority(priority, for: axis)
        }
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
            fatalError("Priority cannot be higher than 'required'")
        }
        self.priority = constraint.priority + 1
        return self
    }

    func priority(lowerThan constraint: NSLayoutConstraint) -> NSLayoutConstraint {
        guard constraint.priority.rawValue > 0 else {
            fatalError("Priority cannot be lower than 0")
        }
        self.priority = constraint.priority - 1
        return self
    }

}

extension Array where Element: NSLayoutConstraint {
    
    func priority(_ value: UILayoutPriority) -> [NSLayoutConstraint] {
        self.map { $0.priority(value) }
    }

    func priority(_ value: Int) -> [NSLayoutConstraint] {
        return self.priority(UILayoutPriority(rawValue: Float(value)))
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
        fatalError("init(coder:) has not been implemented")
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
        fatalError("init(coder:) has not been implemented")
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

protocol BindableViewable: AnyObject, Bindable, ViewWrapper {
    associatedtype WrappedView: ViewWrapper
}

/// A ViewBuilder is a type which has all necessary information to build a `BindableView`.
protocol ViewBuilder {
    associatedtype BuildType: BindableViewable

    /// Builds a `BindableViewable`. In current implementation the `BindableViewable`
    /// is either a `ImmutableBindableViewable` or a `MutableBindableViewable`.
    ///
    /// - A `ImmutableBindableViewable` should ignore the `container` parameter, and never rely on it.
    /// This value may or may not be nil, depending on whether the `container` is being re-used.
    ///
    /// - A `MutableBindableViewable` should add it's views to the passed in `container`.
    /// In this case the passed in `container` will always be non-nil.
    func build(_ container: UIView?) -> BuildType
}

extension ViewBuilder {
    
    func buildView(addTo container: UIView) -> BuildType {
        
        container.translatesAutoresizingMaskIntoConstraints = false
        
        // Cleans up the container
        container.subviews.forEach { $0.removeFromSuperview() }
        
        let binding = self.build(container)
        
        switch binding {
            
        case is MutableBindableViewable<BuildType.BindingType, BuildType.WrappedView>:
            return binding
            
        case is ImmutableBindableViewable<BuildType.BindingType, BuildType.WrappedView>:

            container.addSubview(binding.view)
            binding.view.activateConstraints {
                $0.constraintToParent(.top(0, .belowRequired),
                                      .bottom(0, .belowRequired),
                                      .leading(0, .belowRequired),
                                      .trailing(0, .belowRequired))
            }
            
            return binding
            
        default:
            fatalError("not implemented")
        }
        
    }
    
}

/// A type that wraps a `UIView` object.
/// - Note:`UIView` itself conforms to Viewable.
protocol ViewWrapper {
    var view: UIView { get }
}

extension UIView: ViewWrapper {
    var view: UIView { self }
}

final class ImmutableBindableViewable<BindingType: Equatable, WrappedView: ViewWrapper>: BindableViewable {
    typealias WrappedView = WrappedView
    typealias BindingType = BindingType

    var view: UIView { viewable.view }

    private var state: BindingType? = nil
    private let viewable: WrappedView
    private let binding: (BindingType) -> Void

    init(viewable: WrappedView, _ bindingWrapper: (WrappedView) -> ((BindingType) -> Void)) {
        self.viewable = viewable
        self.binding = bindingWrapper(viewable)
    }

    func bind(_ newValue: BindingType) {
        // As an optimization, skips calling bind if `newValue`
        // is not different from the current state.
        if let current = self.state, newValue == current {
            return
        }
        self.state = newValue
        
        binding(newValue)
    }

}

/// Wraps a `Viewable` that can be mutated.
final class MutableBindableViewable<BindingType: Equatable, WrappedView: ViewWrapper>: BindableViewable {
    typealias WrappedView = WrappedView
    typealias BindingType = BindingType

    var view: UIView { viewable!.view }

    private var state: BindingType? = nil
    private var viewable: WrappedView?
    private let bindingWrapper: (WrappedView?) -> ((BindingType) -> WrappedView?)

    init(viewable: WrappedView?,
         _ bindingWrapper: @escaping (WrappedView?) -> ((BindingType) -> WrappedView?)) {
        self.viewable = viewable
        self.bindingWrapper = bindingWrapper
    }

    func bind(_ newValue: BindingType) {
        // As an optimization, skips calling bind if `newValue`
        // is not different from the current state.
        if let current = self.state, newValue == current {
            return
        }
        self.state = newValue
        
        viewable = bindingWrapper(viewable)(newValue)
    }

}

extension UIAlertAction {

    static func defaultButton(title: String, handler: @escaping () -> Void) -> UIAlertAction {
        .init(title: title, style: .default) { _ in
            handler()
        }
    }

    static func okButton(
        style: Style = .default, _ handler: @escaping () -> Void
    ) -> UIAlertAction {
        .init(title: UserStrings.OK_button_title(), style: style) { _ in
            handler()
        }
    }

    static func dismissButton(
        style: Style = .cancel, _ handler: @escaping () -> Void
    ) -> UIAlertAction {
        .init(title: UserStrings.Dismiss_button_title(), style: style) { _ in
            handler()
        }
    }

}

extension UIAlertController {

    static func makeAlert(
        title: String,
        message: String,
        actions: [UIAlertAction]
    ) -> UIAlertController {

        let alertController = UIAlertController(
            title: title,
            message: message,
            preferredStyle: .alert
        )

        for action in actions {
            alertController.addAction(action)
        }

        return alertController
    }

}

// MARK: ViewController presentation

/// Represents the state of a view that can fail to present.
/// This sturcture wraps the view's view model.
struct PresentationState<ViewModel: Hashable>: Hashable {

    enum State: Hashable {

        /// List of all possible reasons presentation of a view controller might fail.
        enum FailureReason: Hashable {
            case applicationNotActive
        }

        case notPresented
        case willPresent
        case didPresent
        case failedToPresent(FailureReason)
    }

    let viewModel: ViewModel
    var state: State

    init(_ wrappedValue: ViewModel, state: State) {
        self.viewModel = wrappedValue
        self.state = state
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(viewModel)
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.viewModel == rhs.viewModel
    }

}

extension UIViewController {

    func topMostController() -> UIViewController {
        var topController: UIViewController? = self
        while (topController?.presentedViewController) != nil {
            topController = topController?.presentedViewController
        }
        return topController!
    }

}

extension UIViewController {
    
    /// Represents result of traversing presenting stack search for view controller with type `ViewController`.
    enum ViewControllerPresent<ViewController: UIViewController> : Equatable {
        /// Indicates that the view controller is not present in the presenting stack.
        case notPresent
        /// Indicates that the view controller is present in the presenting stack, but is not top of the stack.
        case presentInStack(ViewController)
        /// Indicates that the view controller is present in presenting stack, and is top of the stack.
        case presentTopOfStack(ViewController)
    }
    
    func traversePresentingStackFor<ViewController: UIViewController>(
        type: ViewController.Type,
        searchChildren: Bool = true
    ) -> ViewControllerPresent<ViewController> {
        
        if let viewController = UIViewController.traversePresentingStackFor(
            viewControllerType: type, startingFrom: self, searchChildren: searchChildren
        ) {
            if viewController == self && viewController.presentedViewController == nil {
                return .presentTopOfStack(viewController)
            } else {
                return .presentInStack(viewController)
            }
        } else {
            return .notPresent
        }
    }
    
    /// Traverses the presenting stack starting from `topViewController`, searching for view controller
    /// with type `viewControllerType`.
    /// - Parameter searchChildren: Also searches children in the view controller hierarchy.
    static func traversePresentingStackFor<ViewController: UIViewController>(
        viewControllerType: ViewController.Type,
        startingFrom topViewController: UIViewController,
        searchChildren: Bool = true
    ) -> ViewController? {
        
        if let viewController = topViewController as? ViewController {
            return .some(viewController)
        }
        
        // NOTE: Current implementation limits itself to only the last child added.
        if searchChildren {
            if let viewController = topViewController.children.last as? ViewController {
                return .some(viewController)
            }
        }
        
        if let parent = topViewController.presentingViewController {
            return traversePresentingStackFor(viewControllerType: viewControllerType,
                                              startingFrom: parent)
        }
        
        return .none
    }
    
    /// Presents view controller of type `T` if it is not aleady present in the view controller stack,
    /// either as a view controller that was presented modally or as a view controller presented as
    /// child of a container view controller (e.g. `UINavigationController`).
    ///  - Parameter navigationBar: if `true` wraps view controller returned by `builder`
    ///  in a `PsiNavigationController`.
    ///  - Returns: The top view controller of type `T` if already present in the stack,
    ///  or view controller created by calling `builder`.
    func presentIfTypeNotPresent<T: UIViewController>(
        builder: () -> T, navigationBar: Bool = false, animated: Bool = true
    ) -> T {
        
        // This view controller should be on top of the stack.
        precondition(self.presentedViewController == nil)
        
        // When a view controller is presented with this method,
        // it's identity is tied to it's type. Therefore T should be an
        // identifiable type and not a type that is subclassed (e.g. UIViewController).
        precondition(T.self != UIViewController.self, "Expected a subtype of UIViewController")
        
        let searchResult = self.traversePresentingStackFor(type: T.self, searchChildren: true)
        
        switch searchResult {
        case .presentInStack(let vc):
            return vc
            
        case .presentTopOfStack(let vc):
            return vc
            
        case .notPresent:
            let vc = builder()
            if navigationBar {
                let nav = PsiNavigationController(rootViewController: vc)
                self.present(nav, animated: animated, completion: nil)
            } else {
                self.present(vc, animated: animated, completion: nil)
            }
            return vc
            
        }
        
    }
    
}

// MARK: -

extension UINavigationBar {
    
    /// Hides iOS default 1px bottom border from navigation bar.
    func hideSystemBottomBorder() {
        self.setValue(true, forKey: "hidesShadow")
    }
    
    @objc func applyStandardAppearanceToScrollEdge() {
        if #available(iOS 13.0, *) {
            scrollEdgeAppearance = standardAppearance
        }
    }
    
    /// Applies the following appearance changes to UINavigationBar
    /// - Opaque dark blue background
    /// - Sets title color and font
    /// - Removes iOS default bottom border line
    @objc func applyPsiphonNavigationBarStyling() {
        
        if #available(iOS 13.0, *) {
            
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .darkBlue()
            
            // Removes bottom border line
            appearance.shadowColor = .clear
            
            appearance.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: UIColor.blueGrey(),
                NSAttributedString.Key.font: UIFont.avenirNextBold(15.0)
            ]
            
            self.standardAppearance = appearance
            
            // Applies standard appearance to scoll edge
            self.scrollEdgeAppearance = self.standardAppearance
            
        } else {
            
            // Fallback on earlier versions
            
            self.barStyle = .black
            self.barTintColor = .darkBlue()
            self.isTranslucent = false
            
            // Removes the default iOS bottom border.
            self.setValue(NSNumber(value: true), forKey: "hidesShadow")
            
            self.titleTextAttributes = [
                NSAttributedString.Key.foregroundColor: UIColor.blueGrey(),
                NSAttributedString.Key.font: UIFont.avenirNextBold(15.0)
            ]
            
        }
        
    }
    
}
