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
import Utilities
import PsiApi
import PsiCashClient

struct SpeedBoostPurchasableViewModel: Equatable {
    
    let purchasable: SpeedBoostPurchasable
    let localizedProductTitle: String
    
    var background: SpeedBoostPurchaseBackground {
        return .background(speedBoostDistinguisher: purchasable.product.distinguisher)
    }
    
}

extension SpeedBoostPurchasableViewModel: Comparable {
    
    static func < (lhs: Self, rhs: Self) -> Bool {
        // Compared by hours of Speed Boost.
        lhs.purchasable.product.hours < rhs.purchasable.product.hours
    }
    
}

struct SpeedBoostPurchaseTable: ViewBuilder {

    let purchaseHandler: (SpeedBoostPurchasable) -> Void

    func build(_ container: UIView?)
        -> ImmutableBindableViewable<NonEmpty<SpeedBoostPurchasableViewModel>, SpeedBoostCollection> {
            .init(viewable: SpeedBoostCollection(purchaseHandler: purchaseHandler))
            { table -> ((NonEmpty<SpeedBoostPurchasableViewModel>) -> Void) in
                return {
                    table.bind($0)
                }
            }
    }
}

final class SpeedBoostCollection: NSObject, ViewWrapper, Bindable {
    typealias BindingType = NonEmpty<SpeedBoostPurchasableViewModel>

    // Cell types
    private let HeaderCellIdentifier = "headerCell"
    private let SpeedBoostPurchaseCellIdentifier = "purchaseCell"
    
    // Minimum interitem and line spacing.
    private let minimumSpacing: CGFloat = 5.0
    
    private let itemsPerRow: CGFloat = 3
    
    private let psiCashPriceFormatter = PsiCashAmountFormatter(locale: Locale.current)
    
    private var data: BindingType?
    private let collectionView: UICollectionView
    private let purchaseHandler: (SpeedBoostPurchasable) -> Void

    var view: UIView { collectionView }
    
    var flowLayout: UICollectionViewFlowLayout {
        collectionView.collectionViewLayout as! UICollectionViewFlowLayout
    }

    init(purchaseHandler: @escaping (SpeedBoostPurchasable) -> Void) {
        self.purchaseHandler = purchaseHandler
        collectionView = UICollectionView(frame: .zero,
                                          collectionViewLayout: UICollectionViewFlowLayout())
        super.init()

        collectionView.dataSource = self
        collectionView.delegate = self
        
        // Registers cell types
        
        collectionView.register(SpeedBoostExplainerCell.self,
                                forCellWithReuseIdentifier: HeaderCellIdentifier)
        
        collectionView.register(SpeedBoostPurchaseCell.self,
                                forCellWithReuseIdentifier: SpeedBoostPurchaseCellIdentifier)

        // UI Properties
        collectionView.backgroundColor = .clear
        collectionView.contentInset.bottom = Style.default.screenBottomOffset
        
        // estimatedItemSize is set to a non-zero value (.automaticSize).
        // This causes the collection view to query each cell for its actual size
        // using the cell’s preferredLayoutAttributesFitting(_:) method.
        self.flowLayout.estimatedItemSize = UICollectionViewFlowLayout.automaticSize
        
        self.flowLayout.minimumInteritemSpacing = minimumSpacing
        self.flowLayout.minimumLineSpacing = minimumSpacing
        
    }

    func bind(_ newValue: NonEmpty<SpeedBoostPurchasableViewModel>) {
        guard data != newValue else { return }
        data = newValue
        collectionView.reloadData()
    }
}

// MARK: UICollectionViewDataSource

extension SpeedBoostCollection: UICollectionViewDataSource {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        
        switch section {
        case 0:
            return 1
        case 1:
            return data?.count ?? 0
        default:
            fatalError()
        }
        
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        switch indexPath.section {
        case 0:
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: HeaderCellIdentifier, for: indexPath)
            
            return cell
            
        case 1:
            
            let cell = collectionView.dequeueReusableCell(
                withReuseIdentifier: SpeedBoostPurchaseCellIdentifier, for: indexPath
            ) as! SpeedBoostPurchaseCell
                        
            cell.bind(
                data: data![indexPath.row],
                psiCashPriceFormatter: self.psiCashPriceFormatter,
                purchaseHandler: self.purchaseHandler
            )
            
            return cell
        
            
        default:
            fatalError()
        }
        
    }

}

// MARK: UICollectionViewDelegateFlowLayout

extension SpeedBoostCollection: UICollectionViewDelegateFlowLayout {

    func collectionView(
        _ collectionView: UICollectionView,
        layout collectionViewLayout: UICollectionViewLayout,
        sizeForItemAt indexPath: IndexPath
    ) -> CGSize {
        
        // The CGSize for item at indexPath calculated here acts as the default
        // layout attribute size. This value is passed as the argument of
        // preferredLayoutAttributesFitting(_:) for each cell,
        // and can be modified by the cell.
        //
        // Note that this behaviour exists since `containerView.estimatedItemSize`
        // is set to `.automaticSize`, otherwise preferredLayoutAttributesFitting(_:)
        // will not get called.
        
        switch indexPath.section {

        case 0:
            // Height is determined by the self-sizing cell, it only needs to be a non-zero value.
            return CGSize(width: collectionView.bounds.width, height: 50)

        case 1:
            let totalPaddingInRow = minimumSpacing * (itemsPerRow - 1)
            let totalAvailableWidth = collectionView.bounds.width - totalPaddingInRow
            let availableWidthPerItem = (totalAvailableWidth / itemsPerRow).rounded(.towardZero)
            
            // Height is determined by the self-sizing cell, it only needs to be a non-zero value.
            return CGSize(width: availableWidthPerItem, height: 50)

        default:
            fatalError()

        }

    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        return .zero
    }

}

// MARK: SpeedBoostExplainerCell

fileprivate final class SpeedBoostExplainerCell: UICollectionViewCell {

    private let title: UILabel
    private let subtitle: UILabel
        
    override init(frame: CGRect) {
        
        title = .make(text: UserStrings.Speed_and_port_limits_header(),
                      fontSize: .h2,
                      typeface: .demiBold,
                      color: .white,
                      numberOfLines: 1,
                      alignment: .center)
        
        subtitle = .make(text: UserStrings.Speed_and_port_limibts_body(),
                         fontSize: .normal,
                         typeface: .medium,
                         color: .white,
                         numberOfLines: 0,
                         alignment: .center)
        
        super.init(frame: frame)
        
        // Adds Subviews
        contentView.addSubviews(title, subtitle)
        
        // Sets auto layout constraints
        title.activateConstraints {
            $0.constraintToParent(.top(0), .leading(0), .trailing(0))
        }
        
        subtitle.activateConstraints {
            [
                $0.topAnchor.constraint(
                    equalTo: title.bottomAnchor, constant: Style.default.padding)
            ] +
            $0.constraintToParent(.leading(0), .trailing(0), .bottom(-20))
        }

    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
                            
        // Cell is expected to fit the given calculated width `layoutAttributes.size.width`.
        // This value is calcualted as part collectionView(_:layout:sizeForItemAt:)
        let autoLayoutSize = contentView.systemLayoutSizeFitting(
            layoutAttributes.size,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        
        layoutAttributes.frame = CGRect(origin: layoutAttributes.frame.origin,
                                        size: autoLayoutSize)
        
        return layoutAttributes
    }
    
}

// MARK: PurchaseCellContent

fileprivate final class SpeedBoostPurchaseCell: UICollectionViewCell {
    
    private var purchasable: SpeedBoostPurchasable? = .none
    
    private let backgroundImage: UIImageView
    private let title = UILabel.make(fontSize: .h3, typeface: .bold)
    private let button = GradientButton(gradient: .grey)
    
    private var purchaseHandler: ((SpeedBoostPurchasable) -> Void)?
    
    override init(frame: CGRect) {
        
        self.backgroundImage = UIImageView.make(image:
            SpeedBoostPurchaseBackground.allCases.randomElement()!.rawValue)
        
        super.init(frame: frame)
        
        self.backgroundColor = .clear
        
        addShadow(toLayer: title.layer)
        let psiCashCoinImage = UIImage(named: "PsiCashCoin")
        button.setImage(psiCashCoinImage, for: .normal)
        button.setImage(psiCashCoinImage, for: .highlighted)
        button.setTitleColor(.darkBlue(), for: .normal)
        button.titleLabel!.font = AvenirFont.bold.font(.h3)
        button.isUserInteractionEnabled = false
        
        contentView.addSubviews(backgroundImage, title, button)
        
        // `backgroundImage` should extend itself to fit parent view (contentView)
        // as much as possible, but still keeping the ratio of it's width to height
        // the same as the image that it contains.
        // This is necessary, since this surface is tappable, and we wouldn't
        // an empty area of the screen to respond to touch events.
        
        backgroundImage.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY()) +
            [
                $0.leadingAnchor.constraint(greaterThanOrEqualTo: contentView.leadingAnchor),
                $0.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor),
                $0.topAnchor.constraint(greaterThanOrEqualTo: contentView.topAnchor),
                $0.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor)
            ]
        }

        title.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY(5))
        }

        button.activateConstraints {
            $0.constraint(to: backgroundImage, .leading(10), .trailing(-10)) +
                [ $0.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2) ]
        }
        
        // Gesture recognizer
        let tapRecognizer = UITapGestureRecognizer(target: self,
                                                   action: #selector(onViewTapped))
        
        // Adds gesture to the background image only, since
        // the entire contentView might not be filled by the image.
        backgroundImage.isUserInteractionEnabled = true
        backgroundImage.addGestureRecognizer(tapRecognizer)
        
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(
        data newValue: SpeedBoostPurchasableViewModel,
        psiCashPriceFormatter: PsiCashAmountFormatter,
        purchaseHandler: @escaping (SpeedBoostPurchasable) -> Void
    ) {
        self.purchaseHandler = purchaseHandler
        self.purchasable = newValue.purchasable
        backgroundImage.image = UIImage(named: newValue.background.rawValue)
        
        title.text = newValue.localizedProductTitle

        button.setTitle(
            psiCashPriceFormatter.string(from: newValue.purchasable.price.inPsi),
            for: .normal)
    }
    
    @objc func onViewTapped() {
        if let purchasable = self.purchasable {
            self.purchaseHandler!(purchasable)
        }
    }

    override func preferredLayoutAttributesFitting(
        _ layoutAttributes: UICollectionViewLayoutAttributes
    ) -> UICollectionViewLayoutAttributes {
                    
        // Cell is expected to fit the given calculated width `layoutAttributes.size.width`.
        // This value is calcualted as part collectionView(_:layout:sizeForItemAt:)
        let autoLayoutSize = contentView.systemLayoutSizeFitting(
            layoutAttributes.size,
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        
        layoutAttributes.frame = CGRect(origin: layoutAttributes.frame.origin,
                                        size: autoLayoutSize)
        
        return layoutAttributes
    }
    
}

// MARK: PurchaseRowCellContent

enum SpeedBoostPurchaseBackground: String, CaseIterable {
    case orange = "SpeedBoostBackground_Orange"
    case pink = "SpeedBoostBackground_Pink"
    case purple = "SpeedBoostBackground_Purple"
    case darkBlue = "SpeedBoostBackground_DarkBlue"
    case blue = "SpeedBoostBackground_Blue"
    case green = "SpeedBoostBackground_Green"
    case lightOrange = "SpeedBoostBackground_LightOrange"
    case yellow = "SpeedBoostBackground_Yellow"
    case limeGreen = "SpeedBoostBackground_LimeGreen"

    static func background(speedBoostDistinguisher: String) -> Self {
        switch speedBoostDistinguisher {
        case "1hr": return .orange
        case "2hr": return .pink
        case "3hr": return .purple
        case "4hr": return .darkBlue
        case "5hr": return .blue
        case "6hr": return .green
        case "7hr": return .lightOrange
        case "8hr": return .yellow
        case "9hr": return .limeGreen
        default: return allCases.randomElement()!
        }
    }
}
