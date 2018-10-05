//
//  SubscriptionStatusView.h
//  Psiphon
//
//  Created by Miro Kuratczyk on 2018-09-19.
//  Copyright © 2018 Psiphon Inc. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SubscriptionStatusView : UIView

- (void)subscriptionActive:(BOOL)subscriptionActive;

@end

NS_ASSUME_NONNULL_END
