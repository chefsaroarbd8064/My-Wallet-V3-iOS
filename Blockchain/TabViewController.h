//
//  MainViewController.h
//  Tube Delays
//
//  Created by Ben Reeves on 10/11/2010.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//
#import "Assets.h"

@protocol AssetDelegate
- (void)didSetAssetType:(AssetType)assetType;
@end

@interface TabViewcontroller : UIViewController <UITabBarDelegate> {
    IBOutlet UITabBarItem *sendButton;
    IBOutlet UITabBarItem *dashBoardButton;
    IBOutlet UITabBarItem *homeButton;
    IBOutlet UITabBarItem *receiveButton;
    IBOutlet UITabBar *tabBar;
    IBOutlet UIView *topBar;
	
    IBOutlet UIView *bannerView;
    IBOutlet UILabel *titleLabel;
	UIViewController *activeViewController;
	UIViewController *oldViewController;
    
	int selectedIndex;
}

@property(nonatomic, retain) UIViewController *activeViewController;
@property(nonatomic, retain) UIViewController *oldViewController;
@property(nonatomic, retain) IBOutlet UIView *contentView;
@property (strong, nonatomic) IBOutlet UISegmentedControl *assetSegmentedControl;
@property (strong, nonatomic) IBOutlet UIView *assetControlContainer;
@property(nonatomic, retain) UIView *menuSwipeRecognizerView;
@property(nonatomic) UIView *tabBarGestureView;
@property (nonatomic) UIView *bannerPricesView;
@property (nonatomic) UIView *bannerSelectorView;
@property(weak, nonatomic) id <AssetDelegate> assetDelegate;
- (void)setActiveViewController:(UIViewController *)nviewcontroller animated:(BOOL)animated index:(int)index;
- (void)addTapGestureRecognizerToTabBar:(UITapGestureRecognizer *)tapGestureRecognizer;
- (void)removeTapGestureRecognizerFromTabBar:(UITapGestureRecognizer *)tapGestureRecognizer;
- (int)selectedIndex;
- (void)updateBadgeNumber:(NSInteger)number forSelectedIndex:(int)index;
- (void)setTitleLabelText:(NSString *)text;

@end
