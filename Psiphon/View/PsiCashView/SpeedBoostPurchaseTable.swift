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

struct SpeedBoostPurchasableViewModel: Equatable {
    let purchasable: SpeedBoostPurchasable
    
    var background: SpeedBoostPurchaseBackground {
        return .background(for: purchasable.product.hours)
    }
}

struct SpeedBoostPurchaseTable: ViewBuilder {

    let purchaseHandler: (SpeedBoostPurchasable) -> Void

    func build(_ container: UIView?)
        -> StrictBindableViewable<NonEmpty<SpeedBoostPurchasableViewModel>, SpeedBoostCollection> {
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

    private let purchaseCell = "purchaseCell"
    private let minimumLineSpacing: CGFloat = 10.0
    private let itemsPerRow: CGFloat = 3
    private let imageAspectRatio: CGFloat = 161 / 119
    private let sectionInsets = UIEdgeInsets(top: 15.0,
                                             left: 15.0,
                                             bottom: 15.0,
                                             right: 15.0)

    private var data: BindingType?
    private let collectionView: UICollectionView
    private let purchaseHandler: (SpeedBoostPurchasable) -> Void

    var view: UIView { collectionView }

    init(purchaseHandler: @escaping (SpeedBoostPurchasable) -> Void) {
        self.purchaseHandler = purchaseHandler
        collectionView = UICollectionView(frame: .zero,
                                          collectionViewLayout: UICollectionViewFlowLayout())
        super.init()

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.register(UICollectionViewCell.self,
                                forCellWithReuseIdentifier: purchaseCell)

        // UI Properties
        collectionView.backgroundColor = .clear
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
        return 1
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        precondition(section == 0)
        return data?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: purchaseCell,
                                                      for: indexPath)

        if cell.contentView.subviews[maybe: 0] == nil {
            let content = PurchaseCellContent(purchaseHandler: self.purchaseHandler)
            cell.contentView.addSubview(content)
            content.activateConstraints { $0.matchParentConstraints() }
            cell.backgroundColor = .clear
        }

        guard let content = cell.contentView.subviews[maybe: 0] as? PurchaseCellContent else {
            fatalError()
        }

        content.bind(data![indexPath.row])
        return cell
    }

}

// MARK: UICollectionViewDelegateFlowLayout

extension SpeedBoostCollection: UICollectionViewDelegateFlowLayout {

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        sizeForItemAt indexPath: IndexPath) -> CGSize {

        let totalPaddingInRow = minimumLineSpacing * (itemsPerRow - 1)
        let totalAvailableWidth = view.frame.width - totalPaddingInRow
        let availableWidthPerItem = totalAvailableWidth / itemsPerRow

        return CGSize(width: availableWidthPerItem,
                      height: availableWidthPerItem * imageAspectRatio)
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        insetForSectionAt section: Int) -> UIEdgeInsets {
        return .zero
    }

    func collectionView(_ collectionView: UICollectionView,
                        layout collectionViewLayout: UICollectionViewLayout,
                        minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return minimumLineSpacing
    }

}


fileprivate final class PurchaseCellContent: UIView, Bindable {
    private var purchasable: SpeedBoostPurchasable? = .none
    private let purchaseHandler: (SpeedBoostPurchasable) -> Void

    private let backgroundView: UIImageView
    private let title = UILabel.make(fontSize: .h3, typeface: .bold)
    private let button = GradientButton(gradient: .grey)

    init(purchaseHandler: @escaping (SpeedBoostPurchasable) -> Void) {
        self.purchaseHandler = purchaseHandler
        self.backgroundView = UIImageView.make(image:
            SpeedBoostPurchaseBackground.allCases.randomElement()!.rawValue)
        super.init(frame: .zero)

        addShadow(toLayer: title.layer)
        let psiCashCoinImage = UIImage(named: "PsiCashCoin")
        button.setImage(psiCashCoinImage, for: .normal)
        button.setImage(psiCashCoinImage, for: .highlighted)
        button.setTitleColor(.darkBlue(), for: .normal)
        button.titleLabel!.font = AvenirFont.bold.font(.h3)

        self.addSubviews(backgroundView, title, button)

        self.backgroundView.activateConstraints {
            $0.matchParentConstraints()
        }

        self.title.activateConstraints {
            $0.constraintToParent(.centerX(), .centerY(5))
        }

        self.button.activateConstraints {
            $0.constraintToParent(.leading(10), .trailing(-10), .bottom(-13)) +
                [ $0.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2) ]
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func bind(_ newValue: SpeedBoostPurchasableViewModel) {
        self.purchasable = newValue.purchasable
        backgroundView.image = UIImage(named: newValue.background.rawValue)
        title.text = "\(newValue.purchasable.product.hours) HOUR"

        button.setTitle(
            Current.psiCashPriceFormatter.string(from: newValue.purchasable.price.inPsi),
            for: .normal)

        button.setEventHandler { [unowned self] in
            self.purchaseHandler(newValue.purchasable)
        }
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

    static func background(for speedBoost: Int) -> Self {
        switch speedBoost {
        case 1: return .orange
        case 2: return .pink
        case 3: return .purple
        case 4: return .darkBlue
        case 5: return .blue
        case 6: return .green
        case 7: return .lightOrange
        case 8: return .yellow
        case 9: return .limeGreen
        default: return allCases.randomElement()!
        }
    }
}
