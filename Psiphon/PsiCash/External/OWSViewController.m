//
//  Copyright (c) 2017 Open Whisper Systems. All rights reserved.
//

#import "OWSViewController.h"
//#import "UIView+OWS.h"

NS_ASSUME_NONNULL_BEGIN

@interface OWSViewController ()

@property (nonatomic, weak) UIView *bottomLayoutView;
@property (nonatomic) NSLayoutConstraint *bottomLayoutConstraint;

@end

#pragma mark -

@implementation OWSViewController

- (void)dealloc
{
    // Surface memory leaks by logging the deallocation of view controllers.
    DDLogVerbose(@"Dealloc: %@", self.class);

    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)autoPinViewToBottomGuideOrKeyboard:(UIView *)view
{
    OWSAssert(view);
    OWSAssert(!self.bottomLayoutConstraint);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillShow:)
                                                 name:UIKeyboardWillShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidShow:)
                                                 name:UIKeyboardDidShowNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillHide:)
                                                 name:UIKeyboardWillHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidHide:)
                                                 name:UIKeyboardDidHideNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardWillChangeFrame:)
                                                 name:UIKeyboardWillChangeFrameNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(keyboardDidChangeFrame:)
                                                 name:UIKeyboardDidChangeFrameNotification
                                               object:nil];

    self.bottomLayoutView = view;
    self.bottomLayoutConstraint = [view autoPinToBottomLayoutGuideOfViewController:self withInset:0];
}

- (void)keyboardWillShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidShow:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidHide:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardWillChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)keyboardDidChangeFrame:(NSNotification *)notification
{
    [self handleKeyboardNotification:notification];
}

- (void)handleKeyboardNotification:(NSNotification *)notification
{
    OWSAssertIsOnMainThread();

    if (self.shouldIgnoreKeyboardChanges) {
        return;
    }

    NSDictionary *userInfo = [notification userInfo];

    NSValue *_Nullable keyboardEndFrameValue = userInfo[UIKeyboardFrameEndUserInfoKey];
    if (!keyboardEndFrameValue) {
        OWSFail(@"%@ Missing keyboard end frame", self.logTag);
        return;
    }

    CGRect keyboardEndFrame = [keyboardEndFrameValue CGRectValue];
    CGRect keyboardEndFrameConverted = [self.view convertRect:keyboardEndFrame fromView:nil];
    // Adjust the position of the bottom view to account for the keyboard's
    // intrusion into the view.
    //
    // On iPhoneX, when no keyboard is present, we include a buffer at the bottom of the screen so the bottom view
    // clears the floating "home button". But because the keyboard includes it's own buffer, we subtract the length
    // (height) of the bottomLayoutGuide, else we'd have an unnecessary buffer between the popped keyboard and the input
    // bar.
    CGFloat offset = -MAX(0, (self.view.height - self.bottomLayoutGuide.length - keyboardEndFrameConverted.origin.y));

    // There's no need to use: [UIView animateWithDuration:...].
    // Any layout changes made during these notifications are
    // automatically animated.
    self.bottomLayoutConstraint.constant = offset;
    [self.bottomLayoutView.superview layoutIfNeeded];
}

@end

NS_ASSUME_NONNULL_END
