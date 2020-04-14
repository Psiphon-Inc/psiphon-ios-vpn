//
//  HyprMX.h
//  HyprMX
//
#import <UIKit/UIKit.h>
//! Project version number for HyprMX_SDK.
FOUNDATION_EXPORT double HyprMXVersionNumber;

//! Project version string for HyprMX_SDK.
FOUNDATION_EXPORT const unsigned char HyprMXVersionString[];

#import <HyprMX/HyprMXPlacement.h>
#import <Foundation/Foundation.h>

@protocol HyprMXInitializationDelegate
@optional
/**
 * The initialization has completed successfully
 */
- (void)initializationDidComplete;

/**
 * The initialization has failed
 */
- (void)initializationFailed;
@end

@class HyprMXPlacement;
@interface HyprMX : NSObject

typedef enum {
    HYPRLogLevelError = 0, // Messages at this level get logged all the time.
    HYPRLogLevelVerbose,   //                               ... only when verbose logging is turned on.
    HYPRLogLevelDebug      //                               ... in debug mode.
} HYPRLogLevel;

typedef enum {
    NOT_INITIALIZED = 0,    // HyprMX has not been initialized yet.
    INITIALIZING,           // Initialiation is in progress.
    INITIALIZATION_FAILED,  // Initialization failed.
    INITIALIZATION_COMPLETE // Initialization completed successfully.
} HyprMXState;

typedef enum {
    CONSENT_STATUS_UNKNOWN = 0,  // consent has not been collected from the user
    CONSENT_GIVEN,               // user has granted consent
    CONSENT_DECLINED             // user has declined
} HyprConsentStatus;

/**
 * Initializes the SDK.
 *
 * @param distributorId The application identifier.
 * @param userId Unique ID to identify the user
 * @param initializationDelegate The initialization listener the SDK should callback to
 */
+ (void)initializeWithDistributorId:(NSString *)distributorId
                             userId:(NSString *)userId
             initializationDelegate:(id<HyprMXInitializationDelegate>)initializationDelegate;

/**
 * Initializes the SDK with param for GDPR compliance.
 *
 * @param distributorId The application identifier.
 * @param userId Unique ID to identify the user
 * @param consentStatus for GDPR compliance
 * @param initializationDelegate The initialization listener the SDK should callback to
 */
+ (void)initializeWithDistributorId:(NSString *)distributorId
                             userId:(NSString *)userId
                      consentStatus:(HyprConsentStatus)consentStatus
             initializationDelegate:(id<HyprMXInitializationDelegate>)initializationDelegate;

/**
 * Gets the placement object associated with the placement ID
 *
 * @param placementID The ID of the placement to retrieve
 * @return The placement with the corresponding ID.  If not found, returns a HyprMXInvalidPlacement
 */
+ (HyprMXPlacement *)getPlacement:(NSString *)placementID;

/**
 * Gets all available placements
 *
 * @return an array of HyprMXPlacement objects
 */
+ (NSArray<HyprMXPlacement*>*)placements;

/**
 * Gets the current initialization status.
 *
* @return HyprMXState value of the initialization status
 */
+ (HyprMXState)initializationStatus;

/**
 * Sets logging to a specific level.
 *
 * @param level The log level to log at. Defaults to HYPRLogLevelError.
 * @discussion Level should not be set above HYPRLogLevelError in production, as excessive logging can hurt performance.
 */
+ (void)setLogLevel:(HYPRLogLevel)level;

/*
 * setter for GDPR compliance as determined by publisher
 * @param consentStatus for GDPR compliance
 * @discussion setting consentStatus will invalidate any existing placements,
    loadAd will have to be called again to show an ad
 */
+ (void)setConsentStatus:(HyprConsentStatus)consentStatus;

@end
