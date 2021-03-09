//
//  GADAdLoaderAdTypes.h
//  Google Mobile Ads SDK
//
//  Copyright 2015 Google LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <GoogleMobileAds/GoogleMobileAdsDefines.h>

typedef NSString *GADAdLoaderAdType NS_STRING_ENUM;

/// Use with GADAdLoader to request native custom template ads. To receive ads, the ad loader's
/// delegate must conform to the GADCustomNativeAdLoaderDelegate protocol. See GADCustomNativeAd.h.
GAD_EXTERN GADAdLoaderAdType _Nonnull const kGADAdLoaderAdTypeCustomNative;

/// Use with GADAdLoader to request Google Ad Manager banner ads. To receive ads, the ad loader's
/// delegate must conform to the GAMBannerAdLoaderDelegate protocol. See GAMBannerView.h.
GAD_EXTERN GADAdLoaderAdType _Nonnull const kGADAdLoaderAdTypeGAMBanner;

/// Use with GADAdLoader to request native ads. To receive ads, the ad loader's delegate must
/// conform to the GADNativeAdLoaderDelegate protocol. See GADNativeAd.h.
GAD_EXTERN GADAdLoaderAdType _Nonnull const kGADAdLoaderAdTypeNative;
