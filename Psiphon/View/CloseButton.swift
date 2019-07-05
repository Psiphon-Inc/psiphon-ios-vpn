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

class CloseButton: AnimatedUIButton {

    override init(frame: CGRect) {
        super.init(frame: frame)

        backgroundColor = .init(white: 1.0, alpha: 0.16)
        layer.masksToBounds = true
        clipsToBounds = false
        contentMode = .center
        contentVerticalAlignment = .fill
        contentHorizontalAlignment = .fill

        let crossImage = UIImage(named: "Cross")!.withRenderingMode(.alwaysTemplate)
        setImage(crossImage, for: .normal)
        setImage(crossImage, for: .highlighted)
        imageView!.contentMode = .scaleAspectFit
        imageView!.tintColor = .softGrey1()
        imageEdgeInsets = UIEdgeInsets(top: 8.0, left: 8.0, bottom: 8.0, right: 8.0)

        addShadow(toLayer: layer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = 0.5 * frame.width
    }

}
