/*
 * Copyright (c) 2018, Psiphon Inc.
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

#import "UIView+Additions.h"


@implementation UIView (Additions)

- (NSLayoutXAxisAnchor *)safeLeadingAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.leadingAnchor;
    } else {
        return self.leadingAnchor;
    }
}

- (NSLayoutXAxisAnchor *)safeTrailingAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.trailingAnchor;
    } else {
        return self.trailingAnchor;
    }
}

- (NSLayoutXAxisAnchor *)safeLeftAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.leftAnchor;
    } else {
        return self.leftAnchor;
    }
}

- (NSLayoutXAxisAnchor *)safeRightAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.rightAnchor;
    } else {
        return self.rightAnchor;
    }
}

- (NSLayoutYAxisAnchor *)safeTopAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.topAnchor;
    } else {
        return self.topAnchor;
    }
}

- (NSLayoutYAxisAnchor *)safeBottomAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.bottomAnchor;
    } else {
        return self.bottomAnchor;
    }
}

- (NSLayoutDimension *)safeWidthAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.widthAnchor;
    } else {
        return self.widthAnchor;
    }
}

- (NSLayoutDimension *)safeHeightAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.heightAnchor;
    } else {
        return self.heightAnchor;
    }
}

- (NSLayoutXAxisAnchor *)safeCenterXAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.centerXAnchor;
    } else {
        return self.centerXAnchor;
    }
}

- (NSLayoutYAxisAnchor *)safeCenterYAnchor {
    if (@available(iOS 11.0, *)) {
        return self.safeAreaLayoutGuide.centerYAnchor;
    } else {
        return self.centerYAnchor;
    }
}

@end
