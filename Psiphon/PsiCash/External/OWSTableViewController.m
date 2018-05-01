//
//  Copyright (c) 2018 Open Whisper Systems. All rights reserved.
//

#import "OWSTableViewController.h"

NS_ASSUME_NONNULL_BEGIN

const CGFloat kOWSTable_DefaultCellHeight = 45.f;

@interface OWSTableContents ()

@property (nonatomic) NSMutableArray<OWSTableSection *> *sections;

@end

#pragma mark -

@implementation OWSTableContents

- (instancetype)init
{
    if (self = [super init]) {
        _sections = [NSMutableArray new];
    }
    return self;
}

- (void)addSection:(OWSTableSection *)section
{
    OWSAssert(section);

    [_sections addObject:section];
}

@end

#pragma mark -

@interface OWSTableSection ()

@property (nonatomic) NSMutableArray<OWSTableItem *> *items;

@end

#pragma mark -

@implementation OWSTableSection

+ (OWSTableSection *)sectionWithTitle:(nullable NSString *)title items:(NSArray<OWSTableItem *> *)items
{
    OWSTableSection *section = [OWSTableSection new];
    section.headerTitle = title;
    section.items = [items mutableCopy];
    return section;
}

- (instancetype)init
{
    if (self = [super init]) {
        _items = [NSMutableArray new];
    }
    return self;
}

- (void)addItem:(OWSTableItem *)item
{
    OWSAssert(item);

    [_items addObject:item];
}

- (NSUInteger)itemCount
{
    return _items.count;
}

@end

#pragma mark -

@interface OWSTableItem ()

@property (nonatomic) OWSTableItemType itemType;
@property (nonatomic, nullable) NSString *title;
@property (nonatomic, nullable) OWSTableActionBlock actionBlock;

@property (nonatomic) OWSTableCustomCellBlock customCellBlock;
@property (nonatomic) UITableViewCell *customCell;
@property (nonatomic) NSNumber *customRowHeight;

@end

#pragma mark -

@implementation OWSTableItem

+ (OWSTableItem *)itemWithTitle:(NSString *)title actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(title.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.actionBlock = actionBlock;
    item.title = title;
    return item;
}

+ (OWSTableItem *)itemWithCustomCell:(UITableViewCell *)customCell
                     customRowHeight:(CGFloat)customRowHeight
                         actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCell);
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = (actionBlock != nil ? OWSTableItemTypeAction : OWSTableItemTypeDefault);
    item.actionBlock = actionBlock;
    item.customCell = customCell;
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                          customRowHeight:(CGFloat)customRowHeight
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [self itemWithCustomCellBlock:customCellBlock actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)itemWithCustomCellBlock:(OWSTableCustomCellBlock)customCellBlock
                              actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customCellBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = (actionBlock != nil ? OWSTableItemTypeAction : OWSTableItemTypeDefault);
    item.actionBlock = actionBlock;
    item.customCellBlock = customCellBlock;
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryDisclosureIndicator];
}

+ (OWSTableItem *)checkmarkItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    return [self itemWithText:text actionBlock:actionBlock accessoryType:UITableViewCellAccessoryCheckmark];
}

+ (OWSTableItem *)itemWithText:(NSString *)text
                   actionBlock:(nullable OWSTableActionBlock)actionBlock
                 accessoryType:(UITableViewCellAccessoryType)accessoryType
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = accessoryType;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)disclosureItemWithText:(NSString *)text
                         customRowHeight:(CGFloat)customRowHeight
                             actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [self disclosureItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    __weak OWSTableItem *weakItem = item;
    item.actionBlock = ^{
        OWSTableItem *strongItem = weakItem;
        OWSAssert(strongItem);
        OWSAssert(strongItem.tableViewController);

        if (actionBlock) {
            actionBlock(strongItem.tableViewController);
        }
    };
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)subPageItemWithText:(NSString *)text
                      customRowHeight:(CGFloat)customRowHeight
                          actionBlock:(nullable OWSTableSubPageBlock)actionBlock
{
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [self subPageItemWithText:text actionBlock:actionBlock];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)actionItemWithText:(NSString *)text actionBlock:(nullable OWSTableActionBlock)actionBlock
{
    OWSAssert(text.length > 0);
    OWSAssert(actionBlock);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.actionBlock = actionBlock;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text
{
    OWSAssert(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        // These cells look quite different.
        //
        // Smaller font.
        cell.textLabel.font = [UIFont ows_regularFontWithSize:15.f];
        // Soft color.
        cell.textLabel.textColor = [UIColor colorWithWhite:0.5f alpha:1.f];
        // Centered.
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)softCenterLabelItemWithText:(NSString *)text customRowHeight:(CGFloat)customRowHeight
{
    OWSAssert(customRowHeight > 0);

    OWSTableItem *item = [self softCenterLabelItemWithText:text];
    item.customRowHeight = @(customRowHeight);
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text
{
    OWSAssert(text.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];
        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)labelItemWithText:(NSString *)text accessoryText:(NSString *)accessoryText
{
    OWSAssert(text.length > 0);
    OWSAssert(accessoryText.length > 0);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];

        UILabel *accessoryLabel = [UILabel new];
        accessoryLabel.text = accessoryText;
        accessoryLabel.textColor = [UIColor lightGrayColor];
        accessoryLabel.font = [UIFont ows_regularFontWithSize:16.0f];
        accessoryLabel.textAlignment = NSTextAlignmentRight;
        [accessoryLabel sizeToFit];
        cell.accessoryView = accessoryLabel;

        cell.userInteractionEnabled = NO;
        return cell;
    };
    return item;
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text isOn:(BOOL)isOn target:(id)target selector:(SEL)selector
{
    return [self switchItemWithText:text isOn:isOn isEnabled:YES target:target selector:selector];
}

+ (OWSTableItem *)switchItemWithText:(NSString *)text
                                isOn:(BOOL)isOn
                           isEnabled:(BOOL)isEnabled
                              target:(id)target
                            selector:(SEL)selector
{
    OWSAssert(text.length > 0);
    OWSAssert(target);
    OWSAssert(selector);

    OWSTableItem *item = [OWSTableItem new];
    item.itemType = OWSTableItemTypeAction;
    __weak id weakTarget = target;
    item.customCellBlock = ^{
        UITableViewCell *cell = [UITableViewCell new];
        cell.textLabel.text = text;
        cell.textLabel.font = [UIFont ows_regularFontWithSize:18.f];
        cell.textLabel.textColor = [UIColor blackColor];

        UISwitch *cellSwitch = [UISwitch new];
        cell.accessoryView = cellSwitch;
        [cellSwitch setOn:isOn];
        [cellSwitch addTarget:weakTarget action:selector forControlEvents:UIControlEventValueChanged];
        cellSwitch.enabled = isEnabled;

        cell.selectionStyle = UITableViewCellSelectionStyleNone;

        return cell;
    };
    return item;
}

- (nullable UITableViewCell *)customCell
{
    if (_customCell) {
        return _customCell;
    }
    if (_customCellBlock) {
        return _customCellBlock();
    }
    return nil;
}

@end

#pragma mark -

@interface OWSTableViewController () <UITableViewDelegate, UITableViewDataSource>

@property (nonatomic) UITableView *tableView;

@end

#pragma mark -

NSString *const kOWSTableCellIdentifier = @"kOWSTableCellIdentifier";

@implementation OWSTableViewController

- (instancetype)init
{
    self = [super init];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (instancetype)initWithNibName:(nullable NSString *)nibNameOrNil bundle:(nullable NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (!self) {
        return self;
    }

    [self owsTableCommonInit];

    return self;
}

- (void)owsTableCommonInit
{
    _contents = [OWSTableContents new];
    self.tableViewStyle = UITableViewStyleGrouped;
}

- (void)loadView
{
    [super loadView];

    OWSAssert(self.contents);

    if (self.contents.title.length > 0) {
        self.title = self.contents.title;
    }

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:self.tableViewStyle];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    // Fix a bug that only affects iOS 11.0.x and 11.1.x.
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 0) && !SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(11, 2)) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        self.tableView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
#pragma clang diagnostic pop
    }
    [self.view addSubview:self.tableView];
    [self.tableView autoPinWidthToSuperview];
    [self.tableView autoPinToTopLayoutGuideOfViewController:self withInset:0];
    [self.tableView autoPinToBottomLayoutGuideOfViewController:self withInset:0];

    [self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:kOWSTableCellIdentifier];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self.navigationController.navigationBar setTranslucent:NO];
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (OWSTableSection *)sectionForIndex:(NSInteger)sectionIndex
{
    OWSAssert(self.contents);
    OWSAssert(sectionIndex >= 0 && sectionIndex < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)sectionIndex];
    return section;
}

- (OWSTableItem *)itemForIndexPath:(NSIndexPath *)indexPath
{
    OWSAssert(self.contents);
    OWSAssert(indexPath.section >= 0 && indexPath.section < (NSInteger)self.contents.sections.count);

    OWSTableSection *section = self.contents.sections[(NSUInteger)indexPath.section];
    OWSAssert(indexPath.item >= 0 && indexPath.item < (NSInteger)section.items.count);
    OWSTableItem *item = section.items[(NSUInteger)indexPath.item];

    return item;
}

- (void)setContents:(OWSTableContents *)contents
{
    OWSAssert(contents);
    OWSAssertIsOnMainThread();

    _contents = contents;

    [self.tableView reloadData];
}

#pragma mark - Table view data source

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    OWSAssert(self.contents);
    return (NSInteger)self.contents.sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    OWSAssert(section.items);
    return (NSInteger)section.items.count;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.headerTitle;
}

- (nullable NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.footerTitle;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];

    item.tableViewController = self;

    UITableViewCell *customCell = [item customCell];
    if (customCell) {
        return customCell;
    }

    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:kOWSTableCellIdentifier];
    OWSAssert(cell);

    cell.textLabel.text = item.title;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.customRowHeight) {
        return [item.customRowHeight floatValue];
    }
    return kOWSTable_DefaultCellHeight;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customHeaderView;
}

- (nullable UIView *)tableView:(UITableView *)tableView viewForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *section = [self sectionForIndex:sectionIndex];
    return section.customFooterView;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];

    if (!section) {
        OWSFail(@"Section index out of bounds.");
        return 0;
    }

    if (section.customHeaderHeight) {
        OWSAssert([section.customHeaderHeight floatValue] > 0);
        return [section.customHeaderHeight floatValue];
    } else if (section.headerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

- (CGFloat)tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)sectionIndex
{
    OWSTableSection *_Nullable section = [self sectionForIndex:sectionIndex];
    if (!section) {
        OWSFail(@"Section index out of bounds.");
        return 0;
    }

    if (section.customFooterHeight) {
        OWSAssert([section.customFooterHeight floatValue] > 0);
        return [section.customFooterHeight floatValue];
    } else if (section.footerTitle.length > 0) {
        return UITableViewAutomaticDimension;
    } else {
        return 0;
    }
}

// Called before the user changes the selection. Return a new indexPath, or nil, to change the proposed selection.
- (nullable NSIndexPath *)tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (!item.actionBlock) {
        return nil;
    }

    return indexPath;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];

    OWSTableItem *item = [self itemForIndexPath:indexPath];
    if (item.actionBlock) {
        item.actionBlock();
    }
}

#pragma mark Index

- (NSInteger)tableView:(UITableView *)tableView sectionForSectionIndexTitle:(NSString *)title atIndex:(NSInteger)index
{
    if (self.contents.sectionForSectionIndexTitleBlock) {
        return self.contents.sectionForSectionIndexTitleBlock(title, index);
    } else {
        return 0;
    }
}

- (nullable NSArray<NSString *> *)sectionIndexTitlesForTableView:(UITableView *)tableView
{
    if (self.contents.sectionIndexTitlesForTableViewBlock) {
        return self.contents.sectionIndexTitlesForTableViewBlock();
    } else {
        return 0;
    }
}

#pragma mark - Presentation

- (void)presentFromViewController:(UIViewController *)fromViewController
{
    OWSAssert(fromViewController);

    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:self];
    self.navigationItem.leftBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop
                                                      target:self
                                                      action:@selector(donePressed:)];

    [fromViewController presentViewController:navigationController animated:YES completion:nil];
}

- (void)donePressed:(id)sender
{
    [self dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - UIScrollViewDelegate

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [self.delegate tableViewWillBeginDragging];
}

@end

NS_ASSUME_NONNULL_END
