/*
 * Copyright (c) 2016, Psiphon Inc.
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

// TODO: rename, these images are no longer thumbs up / thumbs down
#import "FeedbackThumbsCell.h"
#import "PsiphonClientCommonLibraryHelpers.h"

#define kThumbsUpIndex 0
#define kThumbsDownIndex 1

#define kThumbsUpGrayscale @"thumbs-up-grayscale"
#define kThumbsUpColor @"thumbs-up-color"
#define kThumbsDownGrayscale @"thumbs-down-grayscale"
#define kThumbsDownColor @"thumbs-down-color"

#define kTextToButtonSizeRatio 7.0/16
#define kTopToImageOffset 20.0
#define kImageToTextOffset 10.0
#define kTextToBottomOffset 10.0

@implementation FeedbackThumbsCell {
    // Text attributes
    NSString *_thumbsUpText;
    NSString *_thumbsDownText;
    UIFont *_font;

    // Sizing
    CGFloat _maxImageHeight;
    CGFloat _requiredHeight;
    CGFloat _segmentedControlWidth;
    CGFloat _segmentedControlHeight;
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if (self = [super initWithStyle:style reuseIdentifier:reuseIdentifier]) {
        // Styling
        UIColor *highlightTint = [UIColor colorWithRed:0.93 green:0.93 blue:0.93 alpha:0.8];
        _font = [UIFont systemFontOfSize:14.0f];
        self.selectionStyle = UITableViewCellSelectionStyleNone;

        // Localized text
        _thumbsUpText = NSLocalizedStringWithDefaultValue(@"FEEDBACK_THUMBS_UP_TEXT", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Psiphon connects\nand performs the\nway I want it to.", @"Text explaining thumbs up choice in feedback. DO NOT translate the word 'Psiphon'.");
        _thumbsDownText = NSLocalizedStringWithDefaultValue(@"FEEDBACK_THUMBS_DOWN_TEXT", nil, [PsiphonClientCommonLibraryHelpers commonLibraryBundle], @"Psiphon often fails\nto connect or\ndoesn't perform well\nenough." , @"Text explaining thumbs down choice in feedback. DO NOT translate the word 'Psiphon'.");

        // Determine proper dimensions to fit image and localized text
        _maxImageHeight = MAX([PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:kThumbsDownColor].size.height, [PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:kThumbsDownGrayscale].size.height);
        _segmentedControlWidth = self.bounds.size.width;
        _segmentedControlHeight = [self requiredFrameHeight:_maxImageHeight
                                                    strings:[NSArray arrayWithObjects:_thumbsUpText, _thumbsDownText, nil]
                                               textBoxWidth:_segmentedControlWidth cellFont:_font];

        // Create images with text
        UIImage *thumbsUp = [self thumbsImage:kThumbsUpIndex selectedSegmentIndex:-1 withHeight:_segmentedControlHeight];
        UIImage *thumbsDown = [self thumbsImage:kThumbsDownIndex selectedSegmentIndex:-1 withHeight:_segmentedControlHeight];
        NSArray *mySegments = [NSArray arrayWithObjects:thumbsUp, thumbsDown, nil];

        UISegmentedControl *sc = [[UISegmentedControl alloc] initWithItems:mySegments];

        // Sizing
        sc.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleHeight;
        sc.frame = CGRectMake(0, 0, self.bounds.size.width, self.bounds.size.height);
        [sc addTarget:self action:@selector(segmentAction:) forControlEvents:UIControlEventValueChanged];

        // Set tints
        [((UIView *)[sc subviews][0]) setTintColor:highlightTint];
        [((UIView *)[sc subviews][1]) setTintColor:highlightTint];

        // Add UISegmentedControl to cell
        [self.contentView addSubview:sc];
        [self setSegmentedControl:sc];
        _requiredHeight = _segmentedControlHeight;
    }

    return self;
}

#pragma mark - Action handling

// Change images based on user selection
-(void)segmentAction:(UISegmentedControl*)sender {
    [sender setImage:[self thumbsImage:kThumbsUpIndex selectedSegmentIndex:sender.selectedSegmentIndex withHeight:sender.frame.size.height] forSegmentAtIndex:kThumbsUpIndex];
    [sender setImage:[self thumbsImage:kThumbsDownIndex selectedSegmentIndex:sender.selectedSegmentIndex withHeight:sender.frame.size.height] forSegmentAtIndex:kThumbsDownIndex];
}

// Return proper thumb image based on user selection
- (UIImage *)thumbsImage:(NSUInteger)index selectedSegmentIndex:(NSInteger)selectedIndex withHeight:(CGFloat)height
{
    BOOL isThumbsUp = index == kThumbsUpIndex;

    UIImage *image;

    if (index == selectedIndex) {
        image = [PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:isThumbsUp ? kThumbsUpColor : kThumbsDownColor];
    } else {
        image = [PsiphonClientCommonLibraryHelpers imageFromCommonLibraryNamed:isThumbsUp ? kThumbsUpGrayscale : kThumbsDownGrayscale];
    }

    return [self imageWithText:image
                      withText:isThumbsUp ? _thumbsUpText : _thumbsDownText
                     cellWidth:_segmentedControlWidth
                    cellHeight:height
                      cellFont:_font];
}

#pragma mark - Image creation and sizing

// Return the required frame height to display largest button in segmented control (image + text size)
-(CGFloat)requiredFrameHeight:(CGFloat)imageHeight strings:(NSArray*)strings textBoxWidth:(NSInteger)textBoxWidth cellFont:(UIFont*)font {
    NSInteger textWidth = textBoxWidth * kTextToButtonSizeRatio; // Pad the sides of the text as percentage of button width
    CGFloat height = 0;

    // Find the largest text height required (_thumbsUpText vs. _thumbsDownText)
    for (NSString *string in strings) {
        CGRect r = [string boundingRectWithSize:CGSizeMake(textWidth, 0)
                                        options:NSStringDrawingUsesLineFragmentOrigin
                                     attributes:@{NSFontAttributeName:font}
                                        context:nil];
        if (r.size.height > height) {
            height = r.size.height;
        }
    }

    return kTopToImageOffset + imageHeight + kImageToTextOffset + height + kTextToBottomOffset;
}

// Returns a new rectangular image consisting of the provided image and text stacked in the centre
//
//      +-----------+
//      |           |
//      |  <image>  |
//      |           |
//      |  <text>   |
//      |           |
//      +-----------+
//
-(UIImage*)imageWithText:(UIImage*)image withText:(NSString*)text cellWidth:(NSInteger)width cellHeight:(NSInteger)height cellFont:(UIFont*)font
{
    NSInteger textWidth = width * kTextToButtonSizeRatio; // Pad the sides of the text as percentage of button width
    CGRect r = [text boundingRectWithSize:CGSizeMake(textWidth, 0)
                                  options:NSStringDrawingUsesLineFragmentOrigin
                               attributes:@{NSFontAttributeName:font}
                                  context:nil];

    // Size of the new image
    CGSize size = CGSizeMake(width / 2, MAX(height, kTopToImageOffset + _maxImageHeight + kImageToTextOffset + r.size.height + kTextToBottomOffset));

    // Begin rendering image
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(context, [UIColor blackColor].CGColor);

    // Text styling
    NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    style.alignment = NSTextAlignmentCenter;

    // Add provided image to new image
    // Ensure images of different sizes have the same calculated y offset
    CGFloat imageYOffset = (_maxImageHeight - image.size.height) / 2 + kTopToImageOffset;
    [image drawInRect:CGRectMake(0.5 * ( width / 2 - image.size.width ), imageYOffset, image.size.width, image.size.height)];

    // Draw text on new image below the provided image
    UIColor *labelColor;
    if (@available(iOS 13.0, *)) {
        labelColor = UIColor.labelColor;
    } else {
        // Fallback on earlier versions
        labelColor = UIColor.blackColor;
    }

    CGRect textRect = CGRectMake(0.5 * ( width / 2  - textWidth ), _maxImageHeight + kTopToImageOffset + kImageToTextOffset, textWidth, r.size.height);
    [text drawInRect:textRect
      withAttributes:@{NSFontAttributeName: font,
                       NSParagraphStyleAttributeName: style,
                       NSForegroundColorAttributeName: labelColor}];

    // Return the rendered image
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [newImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
}

#pragma mark - Public getters

// Return cell height required to render properly
-(CGFloat)requiredHeight {
    return _requiredHeight;
}

@end
