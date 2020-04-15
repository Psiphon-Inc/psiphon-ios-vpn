//
//  HyprMXPlacement.h
//  HyprMX
//

#import <Foundation/Foundation.h>
@class HYPRController;

typedef enum {
    INVALID = 0,
    INTERSTITIAL,
    REWARDED
} HyprMXPlacementType;

typedef enum {
    NO_FILL = 0,
    DISPLAY_ERROR,
    PLACEMENT_DOES_NOT_EXIST
} HyprMXError;

@protocol HyprMXPlacementDelegate;

@interface HyprMXPlacement : NSObject

/** Gets the type of placement */
@property (assign, nonatomic, readonly) HyprMXPlacementType placementType;

/** Gets the Name of the placement */
@property (strong, nonatomic, readonly) NSString *placementName;

/** delegate for this placement */
@property (weak, nonatomic) id<HyprMXPlacementDelegate> placementDelegate;

+ (NSString *)REWARDED;
+ (NSString *)INTERSTITIAL;

/**  Loads the ads */
- (void)loadAd;

/**
 * Checks to see if there is an ad available
 * @return True if an ad can be shown, false otherwise
 */
- (BOOL)isAdAvailable;

/**
 * Shows the ad associated with this placement. This will call back to:
 * For rewarded placement:
 *  HyprMXPlacementListener.adWillStartForPlacement:
 *  HyprMXPlacementListener.oadDidRewardForPlacement:rewardName:rewardValue:
 *  HyprMXPlacementListener.adDidCloseForPlacement:didFinishAd:
 *
 * For interstitial placement:
 *  HyprMXPlacementListener.adWillStartForPlacement:
 *  HyprMXPlacementListener.adDidCloseForPlacement:didFinishAd:
 *
 * No ad to display or error occurred during presentation
 *  HyprMXPlacementListener.adWillStartForPlacement:
 *  HyprMXPlacementListener.adDisplayErrorForPlacement:error:
 *  HyprMXPlacementListener.adDidCloseForPlacement:didFinishAd:
 */
- (void)showAd;
                      
@end

@protocol HyprMXPlacementDelegate <NSObject>

/**
 * The ad is about to start showing
 * @param placement The placement being shown
 */
- (void)adWillStartForPlacement:(HyprMXPlacement *)placement;

/**
 * Presentation related to this placement has finished.
 * @param placement The placement that presented
 * @param finished true if ad was finished, false if it was canceled
 */
- (void)adDidCloseForPlacement:(HyprMXPlacement *)placement didFinishAd:(BOOL)finished;

/**
 * There was an error with the placement during presentation.
 * @param placement The placement with the error
 * @param hyprMXError The error that occured
 */
- (void)adDisplayErrorForPlacement:(HyprMXPlacement *)placement error:(HyprMXError)hyprMXError;

/**
 * An ad is available for the placement
 * @param placement The placement that was loaded
 */
- (void)adAvailableForPlacement:(HyprMXPlacement *)placement;

/**
 * There is no fill for the placement
 * @param placement The placement that was loaded
 */
- (void)adNotAvailableForPlacement:(HyprMXPlacement *)placement;

@optional

/**
 * The ad was rewarded for the placement and will be called before ad finished is called
 * This will only be called for rewarded placements
 * @param placement The placement that was rewarded
 * @param rewardName The name of the reward
 * @param rewardValue The value of the reward
 */
- (void)adDidRewardForPlacement:(HyprMXPlacement *)placement rewardName:(NSString *)rewardName rewardValue:(NSInteger)rewardValue;

@end
