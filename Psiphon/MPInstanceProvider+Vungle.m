//
//  MPInstanceProvider+Vungle.m
//  MoPubSDK
//
//  Copyright (c) 2015 MoPub. All rights reserved.
//

#import "MPInstanceProvider+Vungle.h"
#import "MPVungleRouter.h"

@implementation MPInstanceProvider (Vungle)

- (MPVungleRouter *)sharedMPVungleRouter
{
    return [self singletonForClass:[MPVungleRouter class]
                          provider:^id{
                              return [[MPVungleRouter alloc] init];
                          }];
}

@end
