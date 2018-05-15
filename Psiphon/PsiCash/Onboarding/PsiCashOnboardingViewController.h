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

#import <UIKit/UIKit.h>

/* Psiphon onboarding pages */
typedef NS_ENUM(NSInteger, PsiCashOnboardingStep)
{
    PsiCashOnboardingPage1Index,
    PsiCashOnboardingPage2Index,
    PsiCashOnboardingPage3Index
};

@protocol PsiCashOnboardingViewControllerDelegate <NSObject>
- (void)onboardingEnded;
@end

@protocol PsiCashOnboardingChildViewControllerDelegate <NSObject>
- (CGFloat)getTitleOffset;
- (void)onboardingEnded;
- (void)moveToViewAtIndex:(NSInteger)index;
@end

@interface PsiCashOnboardingViewController : UIViewController <UIPageViewControllerDataSource, UIPageViewControllerDelegate, PsiCashOnboardingChildViewControllerDelegate>
@property (nonatomic, weak) id<PsiCashOnboardingViewControllerDelegate> delegate;
@property (strong, nonatomic) UIPageViewController *pageController;
- (void)moveToNextPage;
@end

@protocol PsiCashOnboardingChildViewController <NSObject>
@property (nonatomic, weak) id<PsiCashOnboardingChildViewControllerDelegate> delegate;
@property (assign, nonatomic) NSInteger index;
@end
