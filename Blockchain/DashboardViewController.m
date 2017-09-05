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

@interface CardsViewController ()
@property (nonatomic) UIScrollView *scrollView;
@property (nonatomic) UIView *contentView;
@end

@interface DashboardViewController ()
@property (nonatomic) BCPriceGraphView *graphView;
@end

@implementation DashboardViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // This contentView can be any custom view - intended to be placed at the top of the scroll view, moved down when the cards view is present, and moved back up when the cards view is dismissed
    self.graphView = [[BCPriceGraphView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 320)];
    self.graphView.backgroundColor = [UIColor grayColor];
    [self.scrollView addSubview:self.graphView];
}

- (void)reload
{
    [self reloadCards];
    
    NSURL *URL = [NSURL URLWithString:[URL_SERVER stringByAppendingString:CHARTS_URL_SUFFIX]];
    NSURLRequest *request = [NSURLRequest requestWithURL:URL];
    
    NSURLSessionDataTask *task = [[SessionManager sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            DLog(@"Error getting chart data - %@", [error localizedDescription]);
        } else {
            NSError *jsonError;
            NSDictionary *jsonResponse = [NSJSONSerialization JSONObjectWithData:data options:kNilOptions error:&jsonError];
             DLog(@"%@", jsonResponse);
            
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.graphView setGraphValues:[jsonResponse objectForKey:DICTIONARY_KEY_VALUES]];
            });
        }
    }];
    
    [task resume];
}

@end
