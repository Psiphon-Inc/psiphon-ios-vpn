/*
 * Copyright (c) 2017, Psiphon Inc.
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

#import "PsiCashInfoView.h"

@implementation PsiCashInfoView {
    UITextView *info;
    UIButton *visitPsiCashWebsite;
    UIStackView *stackView;
}

-(id)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        [self setupViews];
        [self addViews];
        [self setupLayoutConstraints];
    }

    return self;
}

- (void)setupViews {
    stackView = [[UIStackView alloc] init];
    stackView.axis = UILayoutConstraintAxisVertical;
    stackView.alignment = UIStackViewAlignmentCenter;
    stackView.spacing = 5.f;

    info = [[UITextView alloc] init];
    info.scrollEnabled = NO;
    info.backgroundColor = [UIColor clearColor];

    // TODO: l10n
    // TODO: fix link generation
    NSMutableAttributedString * attr = [[NSMutableAttributedString alloc] initWithString:@"Want to know about PsiCash™? Visit our website PsiCash.com to learn about how you can earn and use our exciting new digital currency PsiCash™!"];
    [attr addAttribute: NSLinkAttributeName value:@"http://www.psicash.com" range:NSMakeRange(46, 12)];
    UIFont *font = [UIFont systemFontOfSize:14];
    [attr addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attr.length)];

    info.attributedText = attr;
    info.editable = NO;

    info.textColor = [UIColor whiteColor];
    info.textAlignment = NSTextAlignmentCenter;
}

- (void)addViews {
    [self addSubview:stackView];
    [stackView addArrangedSubview:[UIView new]]; // TODO: is this a hack?
    [stackView addArrangedSubview:info];
    [stackView addArrangedSubview:[UIView new]];
}

-  (void)setupLayoutConstraints {
    stackView.translatesAutoresizingMaskIntoConstraints = NO;
    [stackView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor].active = YES;
    [stackView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor].active = YES;
    [stackView.topAnchor constraintEqualToAnchor:self.topAnchor].active = YES;
    [stackView.bottomAnchor constraintEqualToAnchor:self.bottomAnchor].active = YES;

    info.translatesAutoresizingMaskIntoConstraints = NO;
    [info.centerXAnchor constraintEqualToAnchor:stackView.centerXAnchor].active = YES;
    [info.widthAnchor constraintEqualToAnchor:stackView.widthAnchor multiplier:0.75].active = YES;
    [info setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
}

@end
