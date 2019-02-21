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

#import "PsiCashOnboardingInfoViewController.h"
#import "PsiCashView.h"
#import "UIView+AutoLayoutViewGroup.h"

#define k5sScreenWidth 320.f

// 2nd to Nth onboarding screen(s) after the language
// selection screen (OnboardingLanguageViewController).
// These views display onboarding text describing
// Psiphon Browser to the user.
// Note: we should have the full screen to work with
// because OnboardingViewController should not be presenting
// any other views.
@implementation PsiCashOnboardingInfoViewController {
    UIView *contentView;
    UIView *graphic;
    UILabel *titleView;
    UILabel *textView;
    void (^animations)(void);
}

@synthesize index = _index;
@synthesize delegate = delegate;

- (void)viewDidLoad {
    [super viewDidLoad];

    [self addTitleView];
    [self addTextView];
    [self setPageSpecificContent];
    [self addContentView];
    [self setupLayoutConstraints];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (animations != nil) {
        animations();
        animations = nil;
    }
}

- (void)setPageSpecificContent {
    /* Set page specific content */
    switch (self.index) {
        case PsiCashOnboardingPage1Index: {
            [self setGraphicAsCoin];
            titleView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_1_TITLE", nil, [NSBundle mainBundle], @"Say hello to PsiCash", @"Title text on the first PsiCash onboarding screen. The word 'PsiCash' should not be translated or transliterated. PsiCash is a reward system within Psiphon where users can build up credit that they can then spend on 'Speed Boost' (unlimited connection speed) and, in the future, other rewards.");
            textView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_1_TEXT", nil, [NSBundle mainBundle], @"A new way for you to enjoy maximum speeds, absolutely free.", @"Body text on the first PsiCash onboarding screen. This is in reference to the ability to use PsiCash to purchase 'Speed Boost', which grants unlimited network speed through Psiphon.");
            break;
        }
        case PsiCashOnboardingPage2Index: {
            [self setGraphicAsSpeedBoostMeter];
            titleView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_2_TITLE", nil, [NSBundle mainBundle], @"Your PsiCash balance", @"Title text on the second PsiCash onboarding screen. This shows the user's PsiCash balance, which is the amount of credit they have. Note: 'PsiCash' should not be translated or transliterated.");
            textView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_2_TEXT", nil, [NSBundle mainBundle], @"Connect and engage with our content to earn PsiCash.", @"Body text on the second PsiCash onboarding screen. This is telling the user how to earn PsiCash. The user will be rewared for visiting Psiphon-related websites and pages, browsing and interacting with active content. 'Connect' is in the 'Connect to Psiphon' sense; 'engage with our content' is in the sense of 'visit our sites, read our posts, interact and participate with our content'. The English is intentionally somewhat obtuse, but the translation can use whatever works best. Note: 'PsiCash' should not be translated or transliterated.");
            break;
        }
        case PsiCashOnboardingPage3Index: {
            [self setGraphicAsSpeedBoostMeter];
            titleView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_3_TITLE", nil, [NSBundle mainBundle], @"Speed Boost", @"Title text on the third PsiCash onboarding screen. 'Speed Boost' is a reward that can be purchased with PsiCash credit. It provides unlimited network connection speed through Psiphon. Other words that can be used to help with translation are: 'turbo' (like cars), 'accelerate', 'warp speed', 'blast off', or anything that indicates a fast or unrestricted speed.");
            textView.text = NSLocalizedStringWithDefaultValue(@"PSICASH_ONBOARDING_PAGE_3_TEXT", nil, [NSBundle mainBundle], @"When you've collected enough PsiCash, you can activate Speed Boost and enjoy Psiphon at max speed!", @"Body text on the third PsiCash onboarding screen. This indicates that 'Speed Boost' can be purchased with PsiCash credit after earning a sufficient amount. Note: 'PsiCash' should not be translated or transliterated.");
            break;
        }
        default:
            [self onboardingEnded];
            break;
    }
}

- (void)setGraphicAsCoin {
    /* setup graphic view */
    UIImageView *imageView = [[UIImageView alloc] init];
    UIImage *graphicImage = [UIImage imageNamed:@"PsiCash_Coin"];
    if (graphicImage != nil) {
        imageView.image = graphicImage;
    }
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    [imageView.layer setMinificationFilter:kCAFilterTrilinear]; // Prevent aliasing

    graphic = imageView;
    [self.view addSubview:graphic];

    // Setup layout constraints
    CGFloat coinSize = MIN(120, 1.5 * graphicImage.size.width);
    [graphic.bottomAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:coinSize/4].active = YES;
    [graphic.widthAnchor constraintEqualToConstant:coinSize].active = YES;
    [graphic.heightAnchor constraintEqualToConstant:coinSize].active = YES;
    [graphic.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
}

- (void)setGraphicAsSpeedBoostMeter {
    PsiCashSpeedBoostProductSKU *sku = [PsiCashSpeedBoostProductSKU skuWitDistinguisher:@"1h" withHours:[NSNumber numberWithInteger:1] andPrice:[NSNumber numberWithDouble:100e9]];
    PsiCashView *meter = [[PsiCashView alloc] initWithAutoLayout];
    meter.hideRewardedVideoButton = YES;

    PsiCashClientModel *m = [PsiCashClientModel clientModelWithAuthPackage:[[PsiCashAuthPackage alloc] initWithValidTokens:@[@"indicator", @"earner", @"spender"]]
                                                                andBalance:[NSNumber numberWithInteger:0]
                                                      andSpeedBoostProduct:[PsiCashSpeedBoostProduct productWithSKUs:@[sku]]
                                                       andPendingPurchases:nil
                                               andActiveSpeedBoostPurchase:nil
                                                         andRefreshPending:NO];
    m.onboarded = TRUE;

    if (self.index == PsiCashOnboardingPage2Index) {
        [meter bindWithModel:[m copy]];
        // Add earning animation
        if (self.index == PsiCashOnboardingPage2Index) {
            [NSTimer scheduledTimerWithTimeInterval:1.5 repeats:YES block:^(NSTimer * _Nonnull timer) {
                if (m.balance.doubleValue >= 50e9) {
                    m.balance = [NSNumber numberWithInteger:0];
                } else {
                    double increment = 10e9;
                    [PsiCashView animateBalanceChangeOf:[NSNumber numberWithDouble:increment] withPsiCashView:meter inParentView:self.view];
                    m.balance = [NSNumber numberWithDouble:m.balance.doubleValue + increment];;
                }

                [meter bindWithModel:[m copy]];
            }];
        }
    } else if (self.index == PsiCashOnboardingPage3Index) {
        m.balance = [NSNumber numberWithDouble:100e9];
        [meter bindWithModel:[m copy]];
    }

    graphic = meter;
    [self.view addSubview:graphic];

    // Setup layout constraints
    [graphic.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;
    [graphic.bottomAnchor constraintEqualToAnchor:self.view.centerYAnchor constant:0].active = YES;

    CGFloat psiCashViewMaxWidth = 400;
    CGFloat psiCashViewToParentViewWidthRatio = 0.909;
    if (self.view.frame.size.width * psiCashViewToParentViewWidthRatio > psiCashViewMaxWidth) {
        [graphic.widthAnchor constraintEqualToConstant:psiCashViewMaxWidth].active = YES;
    } else {
        [graphic.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:psiCashViewToParentViewWidthRatio].active = YES;
    }

    [graphic.heightAnchor constraintEqualToConstant:146.9].active = YES;
}

- (void)addTitleView {
    /* Setup title view */
    titleView = [[UILabel alloc] init];
    titleView.numberOfLines = 0;
    titleView.adjustsFontSizeToFitWidth = YES;
    titleView.userInteractionEnabled = NO;
    titleView.font = [UIFont boldSystemFontOfSize:(self.view.frame.size.width - k5sScreenWidth) * 0.0134f + 19.0f];
    titleView.textColor = [UIColor whiteColor];
    titleView.textAlignment = NSTextAlignmentCenter;

}

- (void)addTextView {
    /* Setup text view */
    textView = [[UILabel alloc] init];
    textView.numberOfLines = 0;
    textView.adjustsFontSizeToFitWidth = YES;
    textView.userInteractionEnabled = NO;
    textView.font = [UIFont systemFontOfSize:(self.view.frame.size.width - k5sScreenWidth) * 0.0112f + 18.0f];
    textView.textColor = [UIColor whiteColor];
    textView.textAlignment = NSTextAlignmentCenter;
}

- (void)addContentView {
    contentView = [[UIView alloc] init];
    [contentView addSubview:titleView];
    [contentView addSubview:textView];
    [self.view addSubview:contentView];
}

- (void)setupLayoutConstraints {
    /* Setup autolayout */
    graphic.translatesAutoresizingMaskIntoConstraints = NO;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    titleView.translatesAutoresizingMaskIntoConstraints = NO;
    textView.translatesAutoresizingMaskIntoConstraints = NO;

    NSDictionary *viewsDictionary = @{
                                      @"graphic": graphic,
                                      @"contentView": contentView,
                                      @"titleView": titleView,
                                      @"textView": textView
                                      };

    /* contentView's constraints */
    CGFloat contentViewWidthRatio = 0.8f;

    [contentView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:contentViewWidthRatio].active = YES;
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[graphic]-(>=20)-[contentView]|" options:0 metrics:nil views:viewsDictionary]];
    [contentView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor].active = YES;

    /* titleView's constraints */
    [titleView.widthAnchor constraintEqualToAnchor:contentView.widthAnchor].active = YES;

    titleView.preferredMaxLayoutWidth = contentViewWidthRatio * self.view.frame.size.width;
    [titleView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [titleView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    [titleView.heightAnchor constraintLessThanOrEqualToAnchor:contentView.heightAnchor multiplier:.3f].active = YES;
    [titleView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor].active = YES;

    [NSLayoutConstraint constraintWithItem:titleView
                                 attribute:NSLayoutAttributeCenterY
                                 relatedBy:NSLayoutRelationEqual
                                    toItem:contentView
                                 attribute:NSLayoutAttributeCenterY
                                multiplier:.5f constant:0.f].active = YES;

    /* textView's constraints */
    [textView.widthAnchor constraintEqualToAnchor:contentView.widthAnchor].active = YES;

    textView.preferredMaxLayoutWidth = 0.9 * contentViewWidthRatio * self.view.frame.size.width;
    [textView setContentHuggingPriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];
    [textView setContentCompressionResistancePriority:UILayoutPriorityRequired forAxis:UILayoutConstraintAxisVertical];

    [textView.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor].active = YES;

    /* add vertical constraints for contentView's subviews */
    [contentView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:[titleView]-[textView]-(>=0)-|" options:0 metrics:nil views:viewsDictionary]];
}

- (void)onboardingEnded {
    id<PsiCashOnboardingChildViewControllerDelegate> strongDelegate = self.delegate;

    if ([strongDelegate respondsToSelector:@selector(onboardingEnded)]) {
        [strongDelegate onboardingEnded];
    }
}

@end
