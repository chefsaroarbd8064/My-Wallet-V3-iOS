//
//  MainViewController.m
//  Tube Delays
//
//  Created by Ben Reeves on 10/11/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "TabViewController.h"
#import "RootService.h"
#import "UIView+ChangeFrameAttribute.h"

@implementation TabViewcontroller

@synthesize oldViewController;
@synthesize activeViewController;
@synthesize contentView;

- (void)awakeFromNib
{
    [super awakeFromNib];
    
    [self.assetSegmentedControl setTitle:BC_STRING_BITCOIN forSegmentAtIndex:0];
    [self.assetSegmentedControl setTitleTextAttributes:@{NSFontAttributeName : [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL]} forState:UIControlStateNormal];
    [self.assetSegmentedControl setTitle:BC_STRING_ETHER forSegmentAtIndex:1];
    [self.assetSegmentedControl addTarget:self action:@selector(assetSegmentedControlChanged) forControlEvents:UIControlEventValueChanged];
    
    tabBar.delegate = self;
    
    // Default selected: transactions
    selectedIndex = TAB_TRANSACTIONS;
    
    [self setupTabButtons];
}

- (void)viewDidAppear:(BOOL)animated
{
    // Add side bar to swipe open the sideMenu
    if (!_menuSwipeRecognizerView) {
        _menuSwipeRecognizerView = [[UIView alloc] initWithFrame:CGRectMake(0, DEFAULT_HEADER_HEIGHT, 20, self.view.frame.size.height)];
        
        ECSlidingViewController *sideMenu = app.slidingViewController;
        [_menuSwipeRecognizerView addGestureRecognizer:sideMenu.panGesture];
        
        [self.view addSubview:_menuSwipeRecognizerView];
    }
}

- (void)setupTabButtons
{
    NSDictionary *tabButtons = @{BC_STRING_SEND:sendButton, BC_STRING_DASHBOARD:dashBoardButton, BC_STRING_OVERVIEW:homeButton, BC_STRING_REQUEST:receiveButton};
    
    for (UITabBarItem *button in [tabButtons allValues]) {
        NSString *label = [[tabButtons allKeysForObject:button] firstObject];
        button.title = label;
        button.image = [button.image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        button.selectedImage = [button.selectedImage imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal];
        [button setTitleTextAttributes:@{NSFontAttributeName : [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_EXTRA_EXTRA_SMALL], NSForegroundColorAttributeName : COLOR_TEXT_DARK_GRAY} forState:UIControlStateNormal];
        [button setTitleTextAttributes:@{NSFontAttributeName : [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_EXTRA_EXTRA_SMALL], NSForegroundColorAttributeName : COLOR_BLOCKCHAIN_LIGHT_BLUE} forState:UIControlStateSelected];
    }
}

- (void)setActiveViewController:(UIViewController *)nviewcontroller
{
    [self setActiveViewController:nviewcontroller animated:NO index:selectedIndex];
}

- (void)setActiveViewController:(UIViewController *)nviewcontroller animated:(BOOL)animated index:(int)newIndex
{
    if (nviewcontroller == activeViewController)
        return;
    
    self.oldViewController = activeViewController;
    
    activeViewController = nviewcontroller;
    
    [self insertActiveView];
    
    self.oldViewController = nil;
    
    if (animated) {
        CATransition *animation = [CATransition animation];
        [animation setDuration:ANIMATION_DURATION];
        [animation setType:kCATransitionPush];
        [animation setTimingFunction:[CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear]];
        
        if (newIndex > selectedIndex)
            [animation setSubtype:kCATransitionFromRight];
        else
            [animation setSubtype:kCATransitionFromLeft];
        
        [[contentView layer] addAnimation:animation forKey:@"SwitchToView1"];
    }
    
    [self setSelectedIndex:newIndex];
    
    [self updateTopBarForIndex:newIndex];
}

- (void)insertActiveView
{
    if ([contentView.subviews count] > 0) {
        [[contentView.subviews objectAtIndex:0] removeFromSuperview];
    }
    
    [contentView addSubview:activeViewController.view];
    
    //Resize the View Sub Controller
    activeViewController.view.frame = CGRectMake(activeViewController.view.frame.origin.x, activeViewController.view.frame.origin.y, contentView.frame.size.width, activeViewController.view.frame.size.height);
    
    [activeViewController.view setNeedsLayout];
}

- (int)selectedIndex
{
    return selectedIndex;
}

- (void)setSelectedIndex:(int)nindex
{
    selectedIndex = nindex;
    
    tabBar.selectedItem = nil;

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        tabBar.selectedItem = [[tabBar items] objectAtIndex:selectedIndex];
    });
    
    NSArray *titles = @[BC_STRING_SEND, BC_STRING_DASHBOARD, BC_STRING_OVERVIEW, BC_STRING_REQUEST];
    
    if (nindex < titles.count) {
        [self setTitleLabelText:[titles objectAtIndex:nindex]];
    } else {
        DLog(@"TabViewController Warning: no title found for selected index (array out of bounds)");
    }
}

- (void)updateTopBarForIndex:(int)newIndex
{
    if (newIndex == TAB_SEND || newIndex == TAB_RECEIVE) {
        [UIView animateWithDuration:ANIMATION_DURATION animations:^{
            [self.assetControlContainer changeYPosition:ASSET_CONTAINER_Y_POSITION_DEFAULT - TAB_HEADER_HEIGHT_SMALL_OFFSET];
            [topBar changeHeight:TAB_HEADER_HEIGHT_DEFAULT - TAB_HEADER_HEIGHT_SMALL_OFFSET];
        }];
    } else if (newIndex == TAB_DASHBOARD || newIndex == TAB_TRANSACTIONS) {
        
        if (newIndex == TAB_DASHBOARD) {
            [self showPrices];
        } else if (newIndex == TAB_TRANSACTIONS) {
            [self showSelector];
        }
        
        [UIView animateWithDuration:ANIMATION_DURATION animations:^{
            [self.assetControlContainer changeYPosition:ASSET_CONTAINER_Y_POSITION_DEFAULT];
            [topBar changeHeight:TAB_HEADER_HEIGHT_DEFAULT];
        }];
    }
}

- (void)addTapGestureRecognizerToTabBar:(UITapGestureRecognizer *)tapGestureRecognizer
{
    if (!self.tabBarGestureView) {
        self.tabBarGestureView = [[UIView alloc] initWithFrame:tabBar.bounds];
        self.tabBarGestureView.userInteractionEnabled = YES;
        [self.tabBarGestureView addGestureRecognizer:tapGestureRecognizer];
        [tabBar addSubview:self.tabBarGestureView];
    }
}

- (void)removeTapGestureRecognizerFromTabBar:(UITapGestureRecognizer *)tapGestureRecognizer
{
    [self.tabBarGestureView removeGestureRecognizer:tapGestureRecognizer];
    [self.tabBarGestureView removeFromSuperview];
    self.tabBarGestureView = nil;
}

- (void)tabBar:(UITabBar *)tabBar didSelectItem:(UITabBarItem *)item
{
    if (item == sendButton) {
        [app.tabControllerManager sendCoinsClicked:item];
    } else if (item == homeButton) {
        [app.tabControllerManager transactionsClicked:item];
    } else if (item == receiveButton) {
        [app.tabControllerManager receiveCoinClicked:item];
    } else if (item == dashBoardButton) {
        [app.tabControllerManager dashBoardClicked:item];
    }
}

- (void)updateBadgeNumber:(NSInteger)number forSelectedIndex:(int)index
{
    NSString *badgeString = number > 0 ? [NSString stringWithFormat:@"%lu", number] : nil;
    [[[tabBar items] objectAtIndex:index] setBadgeValue:badgeString];
}

- (void)setTitleLabelText:(NSString *)text
{
    titleLabel.text = text;
    titleLabel.hidden = NO;
}

- (void)assetSegmentedControlChanged
{
    AssetType asset = self.assetSegmentedControl.selectedSegmentIndex;
    [self.assetDelegate didSetAssetType:asset];
}

- (void)didFetchEthExchangeRate
{
    [self updateTopBarForIndex:self.selectedIndex];
}

- (void)showPrices
{
    if (!self.bannerPricesView) {
        
        CGFloat bannerViewHeight = bannerView.frame.size.height;
        CGFloat imageViewWidth = bannerViewHeight - 8;
        
        self.bannerPricesView = [[UIView alloc] initWithFrame:bannerView.bounds];
        
        UIImageView *btcIcon = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, imageViewWidth, bannerViewHeight)];
        [self.bannerPricesView addSubview:btcIcon];
        
        CGFloat btcPriceLabelOriginX = btcIcon.frame.origin.x + btcIcon.frame.size.width + 8;
        UILabel *btcPriceLabel = [[UILabel alloc] initWithFrame:CGRectMake(btcPriceLabelOriginX, 0, bannerView.bounds.size.width/2 - btcPriceLabelOriginX, bannerViewHeight)];
        btcPriceLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_EXTRALIGHT size:FONT_SIZE_SMALL];
        btcPriceLabel.textColor = [UIColor whiteColor];
        btcPriceLabel.text = CURRENCY_SYMBOL_BTC;
        [self.bannerPricesView addSubview:btcPriceLabel];
        self.btcPriceLabel = btcPriceLabel;
        
        UIImageView *etherIcon = [[UIImageView alloc] initWithFrame:CGRectMake(bannerView.bounds.size.width/2, 0, imageViewWidth, bannerViewHeight)];
        [self.bannerPricesView addSubview:etherIcon];
        
        CGFloat ethPriceLabelOriginX = etherIcon.frame.origin.x + etherIcon.frame.size.width;
        UILabel *ethPriceLabel = [[UILabel alloc] initWithFrame:CGRectMake(ethPriceLabelOriginX + 8, 0, bannerView.frame.size.width - ethPriceLabelOriginX, bannerViewHeight)];
        ethPriceLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_EXTRALIGHT size:FONT_SIZE_SMALL];
        ethPriceLabel.textColor = [UIColor whiteColor];
        [self.bannerPricesView addSubview:ethPriceLabel];
        self.ethPriceLabel = ethPriceLabel;
    }
    
    self.ethPriceLabel.text = [NSString stringWithFormat:@"%@ %@", [app.wallet getEthBalanceTruncated], CURRENCY_SYMBOL_ETH];
    self.btcPriceLabel.text = [NSNumberFormatter formatMoney:[app.wallet getTotalActiveBalance] localCurrency:NO];
    
    [bannerView addSubview:self.bannerPricesView];
    [self.bannerSelectorView removeFromSuperview];
}

- (void)showSelector
{
    if (!self.bannerSelectorView) {
        self.bannerSelectorView = [[UIView alloc] initWithFrame:bannerView.bounds];
    }
    
    [bannerView addSubview:self.bannerSelectorView];
    [self.bannerPricesView removeFromSuperview];
}

@end
