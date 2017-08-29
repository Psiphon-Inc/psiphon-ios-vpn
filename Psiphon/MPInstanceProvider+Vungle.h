//
//  MPInstanceProvider+Vungle.h
//  MoPubSDK
//
//  Copyright (c) 2015 MoPub. All rights reserved.
//

#import "MPInstanceProvider.h"

@class MPVungleRouter;

@interface MPInstanceProvider (Vungle)

- (MPVungleRouter *)sharedMPVungleRouter;

@end
