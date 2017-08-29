//
//  VungleInterstitialCustomEvent.h
//  MoPubSDK
//
//  Copyright (c) 2013 MoPub. All rights reserved.
//

#if __has_include(<MoPub/MoPub.h>)
    #import <MoPub/MoPub.h>
#else
    #import "MPInterstitialCustomEvent.h"
#endif

/*
 * Please reference the Supported Mediation Partner page at http://bit.ly/2mqsuFH for the
 * latest version and ad format certifications.
 *
 * The Vungle SDK does not provide an "application will leave" callback, thus this custom event
 * will not invoke the interstitialCustomEventWillLeaveApplication: delegate method.
 */
@interface VungleInterstitialCustomEvent : MPInterstitialCustomEvent

/**
 * Registers a Vungle app ID to be used when initializing the Vungle SDK.
 *
 * At initialization, the Vungle SDK requires you to provide your Vungle app ID. When
 * integrating Vungle using a MoPub custom event, this ID is typically configured via your
 * Vungle network settings on the MoPub website. However, if you wish, you may use this method to
 * manually provide the custom event with your app ID.
 *
 * IMPORTANT: If you choose to use this method, be sure to call it before making any ad requests,
 * and avoid calling it more than once. Otherwise, the Vungle SDK may be initialized improperly.
 *
 * **Deprecated**: This method of setting the Vungle app ID is deprecated. Use the MoPub website to set
 * your app ID in your network settings for Vungle. See the Custom Native Network Setup guide for more
 * information. https://dev.twitter.com/mopub/ad-networks/network-setup-custom-native
 */

@end
