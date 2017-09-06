//
//  DashboardViewController.m
//  Blockchain
//
//  Created by kevinwu on 8/23/17.
//  Copyright © 2017 Blockchain Luxembourg S.A. All rights reserved.
//

#import "CardsViewController.h"
#import "RootService.h"
#import "BCCardView.h"
#import "UIView+ChangeFrameAttribute.h"

@interface CardsViewController () <CardViewDelegate, UIScrollViewDelegate>

@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *contentView;

// Onboarding cards
@property (nonatomic) BOOL showCards;
@property (nonatomic) BOOL showBuyAvailableNow;
@property (nonatomic) CGFloat cardsViewHeight;
@property (nonatomic) UIScrollView *cardsScrollView;
@property (nonatomic) UIView *cardsView;
@property (nonatomic) BOOL isUsingPageControl;
@property (nonatomic) UIPageControl *pageControl;
@property (nonatomic) UIButton *startOverButton;
@property (nonatomic) UIButton *closeCardsViewButton;
@property (nonatomic) UIButton *skipAllButton;
@end

@implementation CardsViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    self.automaticallyAdjustsScrollViewInsets = NO;
    
    self.view.frame = CGRectMake(0,
                              TAB_HEADER_HEIGHT_DEFAULT - DEFAULT_HEADER_HEIGHT,
                              [UIScreen mainScreen].bounds.size.width,
                              [UIScreen mainScreen].bounds.size.height - TAB_HEADER_HEIGHT_DEFAULT - DEFAULT_FOOTER_HEIGHT);
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    [self.view addSubview:self.scrollView];
}

- (void)reloadCards
{
    self.showCards = ![[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_SHOULD_HIDE_ALL_CARDS];
    self.showBuyAvailableNow = !self.showCards && ![[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_SHOULD_HIDE_BUY_NOTIFICATION_CARD] && [app.wallet isBuyEnabled];
    
    self.cardsViewHeight = self.showBuyAvailableNow ? 208 : IS_USING_SCREEN_SIZE_4S ? 208 : 240;
    
    if (self.showCards && app.latestResponse.symbol_local) {
        [self setupCardsViewWithConfiguration:CardConfigurationWelcome];
    } else if (self.showBuyAvailableNow) {
        [self setupCardsViewWithConfiguration:CardConfigurationBuyAvailableNow];
    } else if (app.latestResponse.symbol_local) {
        [self removeCardsView];
    }
    
    self.scrollView.contentSize = CGSizeMake(self.view.frame.size.width, self.cardsViewHeight + self.contentView.frame.size.height);
}

- (void)setupCardsViewWithConfiguration:(CardConfiguration)configuration
{
    [self.cardsView removeFromSuperview];
    
    UIView *cardsView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.scrollView.frame.size.width, self.cardsViewHeight)];
    cardsView.clipsToBounds = YES;
    cardsView.backgroundColor = COLOR_TABLE_VIEW_BACKGROUND_LIGHT_GRAY;
    
    if (configuration == CardConfigurationWelcome) {
        self.cardsView = [self configureCardsViewWelcome:cardsView];
    } else if (configuration == CardConfigurationBuyAvailableNow) {
        self.cardsView = [self configureCardsViewBuyAvailableNow:cardsView];
    }
    
    [self.scrollView addSubview:self.cardsView];
    
    [self.contentView changeYPosition:self.cardsViewHeight];
}

#pragma mark - New Wallet Cards

- (UIView *)configureCardsViewBuyAvailableNow:(UIView *)cardsView
{
    BCCardView *buyAvailableNowCard = [[BCCardView alloc] initWithContainerFrame:cardsView.bounds title:[NSString stringWithFormat:@"\n%@ %@", [BC_STRING_BUY_AVAILABLE_NOW_TITLE uppercaseString], @"🎉"] description:BC_STRING_BUY_AVAILABLE_NOW_DESCRIPTION actionType:ActionTypeBuyBitcoinAvailableNow imageName:@"buy_available" reducedHeightForPageIndicator:NO delegate:self];
    
    UIButton *closeButton = [[UIButton alloc] initWithFrame:CGRectMake(buyAvailableNowCard.bounds.size.width - 25, 12.5, 12.5, 12.5)];
    [closeButton setImage:[[UIImage imageNamed:@"close_large"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    closeButton.tintColor = COLOR_TEXT_DARK_GRAY;
    [closeButton addTarget:self action:@selector(closeBuyAvailableNowCard) forControlEvents:UIControlEventTouchUpInside];
    [buyAvailableNowCard addSubview:closeButton];
    
    [cardsView addSubview:buyAvailableNowCard];
    return cardsView;
}

- (UIView *)configureCardsViewWelcome:(UIView *)cardsView
{
    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:cardsView.bounds];
    scrollView.delegate = self;
    scrollView.pagingEnabled = YES;
    scrollView.showsHorizontalScrollIndicator = NO;
    scrollView.scrollEnabled = YES;
    
    NSInteger numberOfPages = 1;
    NSInteger numberOfCards = 0;
    
    // Cards setup
    if ([app.wallet isBuyEnabled]) {
        
        NSString *tickerText = [NSString stringWithFormat:@"%@ = %@", [NSNumberFormatter formatBTC:[CURRENCY_CONVERSION_BTC longLongValue]], [NSNumberFormatter formatMoney:SATOSHI localCurrency:YES]];
        
        BCCardView *priceCard = [[BCCardView alloc] initWithContainerFrame:cardsView.bounds title:[NSString stringWithFormat:@"%@\n%@", BC_STRING_OVERVIEW_MARKET_PRICE_TITLE, tickerText] description:BC_STRING_OVERVIEW_MARKET_PRICE_DESCRIPTION actionType:ActionTypeBuyBitcoin imageName:@"btc_partial" reducedHeightForPageIndicator:YES delegate:self];
        [scrollView addSubview:priceCard];
        numberOfCards++;
        numberOfPages++;
    }
    
    BCCardView *receiveCard = [[BCCardView alloc] initWithContainerFrame:cardsView.bounds title:BC_STRING_OVERVIEW_RECEIVE_BITCOIN_TITLE description:BC_STRING_OVERVIEW_RECEIVE_BITCOIN_DESCRIPTION actionType:ActionTypeShowReceive imageName:@"receive_partial" reducedHeightForPageIndicator:YES delegate:self];
    receiveCard.frame = CGRectOffset(receiveCard.frame, [self getPageXPosition:cardsView.frame.size.width page:numberOfCards], 0);
    [scrollView addSubview:receiveCard];
    numberOfCards++;
    numberOfPages++;
    
    BCCardView *QRCard = [[BCCardView alloc] initWithContainerFrame:cardsView.bounds title:BC_STRING_OVERVIEW_QR_CODES_TITLE description:BC_STRING_OVERVIEW_QR_CODES_DESCRIPTION actionType:ActionTypeScanQR imageName:@"qr_partial" reducedHeightForPageIndicator:YES delegate:self];
    QRCard.frame = CGRectOffset(QRCard.frame, [self getPageXPosition:cardsView.frame.size.width page:numberOfCards], 0);
    [scrollView addSubview:QRCard];
    numberOfCards++;
    numberOfPages++;
    
    // Overview complete/last page setup
    CGFloat overviewCompleteCenterX = cardsView.frame.size.width/2 + [self getPageXPosition:cardsView.frame.size.width page:numberOfCards];
    
    UIImageView *checkImageView = [[UIImageView alloc] initWithFrame:CGRectMake(0, 40, 40, 40)];
    checkImageView.image = [[UIImage imageNamed:@"success"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    checkImageView.tintColor = COLOR_BLOCKCHAIN_LIGHT_BLUE;
    checkImageView.center = CGPointMake(overviewCompleteCenterX, checkImageView.center.y);
    [scrollView addSubview:checkImageView];
    
    UILabel *doneTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, checkImageView.frame.origin.y + checkImageView.frame.size.height + 14, 150, 30)];
    doneTitleLabel.textAlignment = NSTextAlignmentCenter;
    doneTitleLabel.textColor = COLOR_BLOCKCHAIN_BLUE;
    doneTitleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_MEDIUM_LARGE];
    doneTitleLabel.adjustsFontSizeToFitWidth = YES;
    doneTitleLabel.text = BC_STRING_OVERVIEW_COMPLETE_TITLE;
    doneTitleLabel.center = CGPointMake(overviewCompleteCenterX, doneTitleLabel.center.y);
    [scrollView addSubview:doneTitleLabel];
    
    UILabel *doneDescriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    doneDescriptionLabel.textAlignment = NSTextAlignmentCenter;
    doneDescriptionLabel.numberOfLines = 0;
    doneDescriptionLabel.textColor = COLOR_TEXT_DARK_GRAY;
    doneDescriptionLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_EXTRA_SMALL];
    doneDescriptionLabel.adjustsFontSizeToFitWidth = YES;
    doneDescriptionLabel.text = BC_STRING_OVERVIEW_COMPLETE_DESCRIPTION;
    [doneDescriptionLabel sizeToFit];
    CGFloat maxDoneDescriptionLabelWidth = 170;
    CGFloat maxDoneDescriptionLabelHeight = 70;
    CGSize labelSize = [doneDescriptionLabel sizeThatFits:CGSizeMake(maxDoneDescriptionLabelWidth, maxDoneDescriptionLabelHeight)];
    CGRect labelFrame = doneDescriptionLabel.frame;
    labelFrame.size = labelSize;
    doneDescriptionLabel.frame = labelFrame;
    doneDescriptionLabel.frame = CGRectMake(0, doneTitleLabel.frame.origin.y + doneTitleLabel.frame.size.height, doneDescriptionLabel.frame.size.width, doneDescriptionLabel.frame.size.height);
    doneDescriptionLabel.center = CGPointMake(overviewCompleteCenterX, doneDescriptionLabel.center.y);
    [scrollView addSubview:doneDescriptionLabel];
    
    scrollView.contentSize = CGSizeMake(cardsView.frame.size.width * (numberOfPages), cardsView.frame.size.height);
    [cardsView addSubview:scrollView];
    self.cardsScrollView = scrollView;
    
    // Subviews that disappear/reappear setup
    CGRect cardRect = [receiveCard frameFromContainer:cardsView.bounds];
    
    self.pageControl = [[UIPageControl alloc] initWithFrame:CGRectMake(0, cardRect.origin.y + cardRect.size.height + 8, 100, 30)];
    self.pageControl.center = CGPointMake(cardsView.center.x, self.pageControl.center.y);
    self.pageControl.numberOfPages = numberOfCards;
    self.pageControl.currentPageIndicatorTintColor = COLOR_BLOCKCHAIN_BLUE;
    self.pageControl.pageIndicatorTintColor = COLOR_BLOCKCHAIN_LIGHTEST_BLUE;
    [self.pageControl addTarget:self action:@selector(pageControlChanged:) forControlEvents:UIControlEventValueChanged];
    [cardsView addSubview:self.pageControl];
    
    self.startOverButton = [[UIButton alloc] initWithFrame:CGRectInset(self.pageControl.frame, -40, -10)];
    [cardsView addSubview:self.startOverButton];
    [self.startOverButton setTitle:BC_STRING_START_OVER forState:UIControlStateNormal];
    [self.startOverButton setTitleColor:COLOR_BLOCKCHAIN_LIGHT_BLUE forState:UIControlStateNormal];
    self.startOverButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    self.startOverButton.hidden = YES;
    [self.startOverButton addTarget:self action:@selector(showFirstCard) forControlEvents:UIControlEventTouchUpInside];
    
    CGFloat closeButtonHeight = 46;
    self.closeCardsViewButton = [[UIButton alloc] initWithFrame:CGRectMake(cardsView.frame.size.width - closeButtonHeight, 0, closeButtonHeight, closeButtonHeight)];
    self.closeCardsViewButton.imageEdgeInsets = UIEdgeInsetsMake(16, 20, 16, 12);
    [self.closeCardsViewButton setImage:[[UIImage imageNamed:@"close"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
    self.closeCardsViewButton.imageView.tintColor = COLOR_LIGHT_GRAY;
    [self.closeCardsViewButton addTarget:self action:@selector(closeCardsView) forControlEvents:UIControlEventTouchUpInside];
    [cardsView addSubview:self.closeCardsViewButton];
    self.closeCardsViewButton.hidden = YES;
    
    CGFloat skipAllButtonWidth = 80;
    CGFloat skipAllButtonHeight = 30;
    self.skipAllButton = [[UIButton alloc] initWithFrame:CGRectMake(cardsView.frame.size.width - skipAllButtonWidth, self.pageControl.frame.origin.y, skipAllButtonWidth, skipAllButtonHeight)];
    self.skipAllButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    self.skipAllButton.backgroundColor = [UIColor clearColor];
    [self.skipAllButton setTitleColor:COLOR_BLOCKCHAIN_LIGHTEST_BLUE forState:UIControlStateNormal];
    [self.skipAllButton setTitle:BC_STRING_SKIP_ALL forState:UIControlStateNormal];
    [self.skipAllButton addTarget:self action:@selector(closeCardsView) forControlEvents:UIControlEventTouchUpInside];
    [cardsView addSubview:self.skipAllButton];
    
    
    // Maintain last viewed page when a refresh is triggered
    CGFloat oldContentOffsetX = [[[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_KEY_LAST_CARD_OFFSET] floatValue];
    if (oldContentOffsetX > scrollView.contentSize.width - scrollView.frame.size.width * 1.5) {
        self.startOverButton.hidden = NO;
        self.closeCardsViewButton.hidden = NO;
        self.pageControl.hidden = YES;
        self.skipAllButton.hidden = YES;
    };
    self.cardsScrollView.contentOffset = CGPointMake(oldContentOffsetX > self.cardsScrollView.contentSize.width ? self.cardsScrollView.contentSize.width - self.cardsScrollView.frame.size.width : oldContentOffsetX, self.cardsScrollView.contentOffset.y);
    
    return cardsView;
}

- (void)showFirstCard
{
    self.cardsScrollView.scrollEnabled = YES;
    [self.cardsScrollView setContentOffset:CGPointZero animated:YES];
    
    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:0] forKey:USER_DEFAULTS_KEY_LAST_CARD_OFFSET];
}

- (CGFloat)getPageXPosition:(CGFloat)cardLength page:(NSInteger)page
{
    return cardLength * page;
}

- (void)closeBuyAvailableNowCard
{
    [self closeCardsView];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_SHOULD_HIDE_BUY_NOTIFICATION_CARD];
}

- (void)cardActionClicked:(ActionType)actionType
{
    if (actionType == ActionTypeBuyBitcoin ||
        actionType == ActionTypeBuyBitcoinAvailableNow) {
        [app buyBitcoinClicked:nil];
    } else if (actionType == ActionTypeShowReceive) {
        [app.tabControllerManager receiveCoinClicked:nil];
    } else if (actionType == ActionTypeScanQR) {
        [app QRCodebuttonClicked:nil];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (scrollView == self.cardsScrollView) {
        
        BOOL didSeeAllCards = scrollView.contentOffset.x > scrollView.contentSize.width - scrollView.frame.size.width * 1.5;
        if (didSeeAllCards) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_HAS_SEEN_ALL_CARDS];
        }
        
        if (!self.isUsingPageControl) {
            CGFloat pageWidth = scrollView.frame.size.width;
            float fractionalPage = scrollView.contentOffset.x / pageWidth;
            
            if (!didSeeAllCards) {
                if (self.skipAllButton.hidden && self.pageControl.hidden) {
                    [UIView animateWithDuration:ANIMATION_DURATION animations:^{
                        self.skipAllButton.alpha = 1;
                        self.pageControl.alpha = 1;
                        self.startOverButton.alpha = 0;
                        self.closeCardsViewButton.alpha = 0;
                    } completion:^(BOOL finished) {
                        self.skipAllButton.hidden = NO;
                        self.pageControl.hidden = NO;
                        self.startOverButton.hidden = YES;
                        self.closeCardsViewButton.hidden = YES;
                    }];
                }
            } else {
                if (!self.skipAllButton.hidden && !self.pageControl.hidden) {
                    [UIView animateWithDuration:ANIMATION_DURATION animations:^{
                        self.skipAllButton.alpha = 0;
                        self.pageControl.alpha = 0;
                        self.startOverButton.alpha = 1;
                        self.closeCardsViewButton.alpha = 1;
                    } completion:^(BOOL finished) {
                        self.skipAllButton.hidden = YES;
                        self.pageControl.hidden = YES;
                        self.startOverButton.hidden = NO;
                        self.closeCardsViewButton.hidden = NO;
                    }];
                }
            }
            
            NSInteger page = lround(fractionalPage);
            self.pageControl.currentPage = page;
        }
    }
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (scrollView == self.cardsScrollView) {
        if (scrollView.contentSize.width - scrollView.frame.size.width <= scrollView.contentOffset.x) {
            scrollView.scrollEnabled = NO;
        }
        
        // Save last viewed page since cards view can be reinstantiated when app is still open
        [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithFloat:scrollView.contentOffset.x] forKey:USER_DEFAULTS_KEY_LAST_CARD_OFFSET];
    }
}

- (void)scrollViewDidEndScrollingAnimation:(UIScrollView *)scrollView
{
    if (scrollView == self.cardsScrollView) {
        self.isUsingPageControl = NO;
    }
}

- (void)pageControlChanged:(UIPageControl *)pageControl
{
    self.isUsingPageControl = YES;
    
    NSInteger page = pageControl.currentPage;
    CGRect frame = self.cardsScrollView.frame;
    frame.origin.x = self.cardsScrollView.frame.size.width * page;
    [self.cardsScrollView scrollRectToVisible:frame animated:YES];
}

- (void)closeCardsView
{    
    [UIView animateWithDuration:ANIMATION_DURATION_LONG animations:^{
        [self.cardsView changeHeight:0];
        self.scrollView.contentSize = CGSizeMake(self.view.frame.size.width, self.contentView ? self.contentView.frame.size.height : 0);
        [self.contentView changeYPosition:0];
    } completion:^(BOOL finished) {
        [self removeCardsView];
    }];
    
    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_SHOULD_HIDE_ALL_CARDS];
}

- (void)removeCardsView
{
    [self.cardsView removeFromSuperview];
    self.cardsView = nil;
    self.scrollView.contentSize = CGSizeMake(self.view.frame.size.width, self.contentView ? self.contentView.frame.size.height : 0);
    [self.contentView changeYPosition:0];
}

@end
