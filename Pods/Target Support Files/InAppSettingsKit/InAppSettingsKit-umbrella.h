#ifdef __OBJC__
#import <UIKit/UIKit.h>
#else
#ifndef FOUNDATION_EXPORT
#if defined(__cplusplus)
#define FOUNDATION_EXPORT extern "C"
#else
#define FOUNDATION_EXPORT extern
#endif
#endif
#endif

#import "IASKAppSettingsViewController.h"
#import "IASKAppSettingsWebViewController.h"
#import "IASKMultipleValueSelection.h"
#import "IASKSpecifierValuesViewController.h"
#import "IASKViewController.h"
#import "IASKSettingsReader.h"
#import "IASKSettingsStore.h"
#import "IASKSettingsStoreFile.h"
#import "IASKSettingsStoreUserDefaults.h"
#import "IASKSpecifier.h"
#import "IASKColor.h"
#import "IASKPSSliderSpecifierViewCell.h"
#import "IASKPSTextFieldSpecifierViewCell.h"
#import "IASKSlider.h"
#import "IASKSwitch.h"
#import "IASKTextField.h"
#import "IASKTextView.h"
#import "IASKTextViewCell.h"

FOUNDATION_EXPORT double InAppSettingsKitVersionNumber;
FOUNDATION_EXPORT const unsigned char InAppSettingsKitVersionString[];

