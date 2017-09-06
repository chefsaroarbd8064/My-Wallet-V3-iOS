//
//  DashboardViewController.m
//  Blockchain
//
//  Created by kevinwu on 8/23/17.
//  Copyright © 2017 Blockchain Luxembourg S.A. All rights reserved.
//

#import "DashboardViewController.h"
#import "SessionManager.h"
#import "BCPriceGraphView.h"
#import "UIView+ChangeFrameAttribute.h"
#import "NSNumberFormatter+Currencies.h"

@interface CardsViewController ()
@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *contentView;
@end

@interface DashboardViewController ()
@property (nonatomic) BCPriceGraphView *graphView;
@property (nonatomic) UILabel *priceLabel;
@property (nonatomic) UIButton *yearButton;
@property (nonatomic) UIButton *monthButton;
@property (nonatomic) UIButton *weekButton;
@property (nonatomic) NSString *lastEthExchangeRate;
@end

@implementation DashboardViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // This contentView can be any custom view - intended to be placed at the top of the scroll view, moved down when the cards view is present, and moved back up when the cards view is dismissed
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 320)];
    self.contentView.clipsToBounds = YES;
    self.contentView.backgroundColor = [UIColor whiteColor];
    [self.scrollView addSubview:self.contentView];
    
    UIView *titleContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 60)];
    titleContainerView.backgroundColor = [UIColor clearColor];
    titleContainerView.center = CGPointMake(self.contentView.center.x, titleContainerView.center.y);
    
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 0, 0)];
    titleLabel.textColor = COLOR_BLOCKCHAIN_BLUE;
    titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_EXTRALIGHT size:FONT_SIZE_EXTRA_SMALL];
    titleLabel.text = [BC_STRING_ETHER_PRICE uppercaseString];
    [titleLabel sizeToFit];
    titleLabel.center = CGPointMake(titleContainerView.frame.size.width/2, titleLabel.center.y);
    [titleContainerView addSubview:titleLabel];
    
    self.priceLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, titleLabel.frame.origin.y + titleLabel.frame.size.height, 0, 0)];
    self.priceLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_LARGE];
    self.priceLabel.textColor = COLOR_BLOCKCHAIN_BLUE;
    [titleContainerView addSubview:self.priceLabel];
    
    [self.contentView addSubview:titleContainerView];
    
    self.graphView = [[BCPriceGraphView alloc] initWithFrame:CGRectInset(self.contentView.bounds, 60, 60)];
    self.graphView.backgroundColor = [UIColor whiteColor];
    [self.graphView changeWidth:self.contentView.frame.size.width - self.graphView.frame.origin.x - 30];
    [self.graphView changeHeight:self.contentView.frame.size.height - 150];
    [self.contentView addSubview:self.graphView];
    
    UIView *verticalBorder = [[UIView alloc] initWithFrame:CGRectMake(self.graphView.frame.origin.x - 1, self.graphView.frame.origin.y, 1, self.graphView.frame.size.height + 1)];
    verticalBorder.backgroundColor = COLOR_LIGHT_GRAY;
    [self.contentView addSubview:verticalBorder];
    
    UIView *horizontalBorder = [[UIView alloc] initWithFrame:CGRectMake(self.graphView.frame.origin.x, self.graphView.frame.origin.y + self.graphView.frame.size.height, self.graphView.frame.size.width, 1)];
    horizontalBorder.backgroundColor = COLOR_LIGHT_GRAY;
    [self.contentView addSubview:horizontalBorder];
    
    [self setupAxes];
    
    [self setupTimeSpanButtons];
}

- (void)reload
{
    self.priceLabel.text = self.lastEthExchangeRate;
    [self.priceLabel sizeToFit];
    self.priceLabel.center = CGPointMake(self.contentView.center.x, self.priceLabel.center.y);
    
    [self reloadCards];
    
    NSURL *URL = [NSURL URLWithString:[URL_SERVER stringByAppendingString:CHARTS_URL_SUFFIX]];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    
    NSURLSessionDataTask *task = [[SessionManager sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            DLog(@"Error getting chart data - %@", [error localizedDescription]);
        } else {
            NSError *jsonError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
//             DLog(@"%@", jsonResponse);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.graphView setGraphValues:[jsonResponse objectForKey:DICTIONARY_KEY_VALUES]];
            });
        }
    }];
    
    [task resume];
}

- (void)setupAxes
{
    [self setupXAxis];
    [self setupYAxis];
}

- (void)setupXAxis
{
    UIView *labelContainerView = [[UIView alloc] initWithFrame:CGRectMake(self.graphView.frame.origin.x, self.graphView.frame.origin.y + self.graphView.frame.size.height + 8, self.graphView.frame.size.width, 30)];
    labelContainerView.backgroundColor = [UIColor clearColor];
    
    UILabel *firstLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    firstLabel.text = @"test";
    firstLabel.center = CGPointMake(labelContainerView.frame.size.width/8, labelContainerView.frame.size.height/2);
    [labelContainerView addSubview:firstLabel];
    
    UILabel *secondLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    secondLabel.text = @"test";
    secondLabel.center = CGPointMake(labelContainerView.frame.size.width/2 - labelContainerView.frame.size.width/8, labelContainerView.frame.size.height/2);
    [labelContainerView addSubview:secondLabel];
    
    UILabel *thirdLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    thirdLabel.text = @"test";
    thirdLabel.center = CGPointMake(labelContainerView.frame.size.width/2 + labelContainerView.frame.size.width/8, labelContainerView.frame.size.height/2);
    [labelContainerView addSubview:thirdLabel];
    
    UILabel *fourthLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    fourthLabel.text = @"test";
    fourthLabel.center = CGPointMake(labelContainerView.frame.size.width*7/8, labelContainerView.frame.size.height/2);
    [labelContainerView addSubview:fourthLabel];
    
    [self.contentView addSubview:labelContainerView];
}

- (void)setupYAxis
{
    UIView *labelContainerView = [[UIView alloc] initWithFrame:CGRectMake(self.graphView.frame.origin.x - 60 - 8, self.graphView.frame.origin.y, 60, self.graphView.frame.size.height)];
    labelContainerView.backgroundColor = [UIColor clearColor];
    
    UILabel *firstLabel = [self axisLabelWithFrame:CGRectMake(0, 0, labelContainerView.frame.size.width, 30)];
    firstLabel.text = @"test";
    firstLabel.center = CGPointMake(labelContainerView.frame.size.width/2, labelContainerView.frame.size.height*7/8);
    [labelContainerView addSubview:firstLabel];
    
    UILabel *secondLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    secondLabel.text = @"test";
    secondLabel.center = CGPointMake(labelContainerView.frame.size.width/2, labelContainerView.frame.size.height/2 + labelContainerView.frame.size.height/8);
    [labelContainerView addSubview:secondLabel];

    UILabel *thirdLabel = [self axisLabelWithFrame:CGRectMake(0, 0, 60, labelContainerView.frame.size.height)];
    thirdLabel.text = @"test";
    thirdLabel.center = CGPointMake(labelContainerView.frame.size.width/2, labelContainerView.frame.size.height/2 - labelContainerView.frame.size.height/8);
    [labelContainerView addSubview:thirdLabel];

    UILabel *fourthLabel = [self axisLabelWithFrame:CGRectMake(0, labelContainerView.frame.size.height/8, 60, labelContainerView.frame.size.height)];
    fourthLabel.text = @"test";
    fourthLabel.center = CGPointMake(labelContainerView.frame.size.width/2, labelContainerView.frame.size.height/8);
    [labelContainerView addSubview:fourthLabel];
    
    [self.contentView addSubview:labelContainerView];
}

- (void)setupTimeSpanButtons
{
    CGFloat buttonContainerViewWidth = 210;
    UIView *buttonContainerView = [[UIView alloc] initWithFrame:CGRectMake(0, self.graphView.frame.origin.y + self.graphView.frame.size.height + 50, buttonContainerViewWidth, 30)];
    
    CGFloat buttonWidth = buttonContainerViewWidth/3;
    
    self.weekButton = [self timeSpanButtonWithFrame:CGRectMake(0, 0, buttonWidth, 30) title:BC_STRING_WEEK];
    [buttonContainerView addSubview:self.weekButton];
    
    self.monthButton = [self timeSpanButtonWithFrame:CGRectMake(self.weekButton.frame.origin.x + buttonWidth, 0, buttonWidth, 30) title:BC_STRING_MONTH];
    [buttonContainerView addSubview:self.monthButton];
    
    self.yearButton = [self timeSpanButtonWithFrame:CGRectMake(self.monthButton.frame.origin.x + buttonWidth, 0, buttonWidth, 30) title:BC_STRING_YEAR];
    [buttonContainerView addSubview:self.yearButton];
    
    [self.contentView addSubview:buttonContainerView];
    buttonContainerView.center = CGPointMake(self.contentView.center.x, buttonContainerView.center.y);
}

- (void)timeSpanButtonTapped:(UIButton *)button
{
    [self.weekButton setSelected:NO];
    [self.monthButton setSelected:NO];
    [self.yearButton setSelected:NO];

    [button setSelected:YES];
}

- (void)updateEthExchangeRate:(NSDecimalNumber *)rate
{
    self.lastEthExchangeRate = [NSNumberFormatter formatEthToFiatWithSymbol:@"1" exchangeRate:rate];
    [self reload];
}

#pragma mark - View Helpers

- (UILabel *)axisLabelWithFrame:(CGRect)frame
{
    UILabel *label = [[UILabel alloc] initWithFrame:frame];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    return label;
}

- (UIButton *)timeSpanButtonWithFrame:(CGRect)frame title:(NSString *)title
{
    UIFont *normalFont = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_EXTRA_SMALL];
    UIFont *selectedFont = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    
    NSAttributedString *attrNormal = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName:normalFont, NSForegroundColorAttributeName:COLOR_BLOCKCHAIN_BLUE, NSUnderlineStyleAttributeName:[NSNumber numberWithInt:NSUnderlineStyleNone]}];
    NSAttributedString *attrSelected = [[NSAttributedString alloc] initWithString:title attributes:@{NSFontAttributeName:selectedFont, NSForegroundColorAttributeName:COLOR_BLOCKCHAIN_BLUE, NSUnderlineStyleAttributeName:[NSNumber numberWithInt:NSUnderlineStyleSingle]}];
    
    UIButton *button = [[UIButton alloc] initWithFrame:frame];
    [button setAttributedTitle:attrNormal forState:UIControlStateNormal];
    [button setAttributedTitle:attrSelected forState:UIControlStateSelected];
    [button addTarget:self action:@selector(timeSpanButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    return button;
}

@end
