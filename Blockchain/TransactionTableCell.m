//
//  TransactionTableCell.m
//  Blockchain
//
//  Created by Ben Reeves on 10/01/2012.
//  Copyright (c) 2012 Blockchain Luxembourg S.A. All rights reserved.
//

#import "TransactionTableCell.h"
#import "Transaction.h"
#import "RootService.h"
#import "TransactionsBitcoinViewController.h"
#import "TransactionDetailViewController.h"
#import "TransactionDetailNavigationController.h"
#import "NSDateFormatter+TimeAgoString.h"

@implementation TransactionTableCell

@synthesize transaction;

- (void)reload
{
    if (transaction == NULL)
        return;
    
    if (transaction.time > 0)  {
        dateLabel.adjustsFontSizeToFitWidth = YES;
        dateLabel.hidden = NO;
        
        NSDate *date = [NSDate dateWithTimeIntervalSince1970:transaction.time];
        
        dateLabel.text = [NSDateFormatter timeAgoStringFromDate:date];
    } else {
        dateLabel.hidden = YES;
    }
    
    btcButton.titleLabel.minimumScaleFactor =  0.75f;
    [btcButton.titleLabel setAdjustsFontSizeToFitWidth:YES];
    
    [btcButton setTitle:[NSNumberFormatter formatMoney:ABS(transaction.amount)] forState:UIControlStateNormal];
    
    if([transaction.txType isEqualToString:TX_TYPE_TRANSFER]) {
        [btcButton setBackgroundColor:COLOR_TRANSACTION_TRANSFERRED];
        actionLabel.text = [BC_STRING_TRANSFERRED uppercaseString];
        actionLabel.textColor = COLOR_TRANSACTION_TRANSFERRED;
    } else if ([transaction.txType isEqualToString:TX_TYPE_RECEIVED]) {
        [btcButton setBackgroundColor:COLOR_TRANSACTION_RECEIVED];
        actionLabel.text = [BC_STRING_RECEIVED uppercaseString];
        actionLabel.textColor = COLOR_TRANSACTION_RECEIVED;
    } else {
        [btcButton setBackgroundColor:COLOR_TRANSACTION_SENT];
        actionLabel.text = [BC_STRING_SENT uppercaseString];
        actionLabel.textColor = COLOR_TRANSACTION_SENT;
    }
    
    watchOnlyLabel.adjustsFontSizeToFitWidth = YES;
    watchOnlyLabel.layer.cornerRadius = 5;
    watchOnlyLabel.clipsToBounds = YES;
    watchOnlyLabel.text = BC_STRING_WATCH_ONLY;
    watchOnlyLabel.customEdgeInsets = UIEdgeInsetsMake(0, 4, 0, 4);
    
    if ((([transaction.txType isEqualToString:TX_TYPE_RECEIVED] || [transaction.txType isEqualToString:TX_TYPE_TRANSFER]) && transaction.toWatchOnly) || ([transaction.txType isEqualToString:TX_TYPE_SENT] && transaction.fromWatchOnly)) {
        watchOnlyLabel.hidden = NO;
        actionLabel.frame = CGRectMake(actionLabel.frame.origin.x, 20, actionLabel.frame.size.width, actionLabel.frame.size.height);
        dateLabel.frame = CGRectMake(dateLabel.frame.origin.x, 3, dateLabel.frame.size.width, dateLabel.frame.size.height);
    } else {
        watchOnlyLabel.hidden = YES;
        actionLabel.frame = CGRectMake(actionLabel.frame.origin.x, 29, actionLabel.frame.size.width, actionLabel.frame.size.height);
        dateLabel.frame = CGRectMake(dateLabel.frame.origin.x, 11, dateLabel.frame.size.width, dateLabel.frame.size.height);
    }
    
    warningImageView.image = [warningImageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    [warningImageView setTintColor:COLOR_WARNING_RED];
    
    if (transaction.doubleSpend || transaction.replaceByFee) {
        warningImageView.hidden = NO;
        actionLabel.frame = CGRectMake(actionLabel.frame.origin.x, actionLabel.frame.origin.y, 152, actionLabel.frame.size.height);
        dateLabel.frame = CGRectMake(dateLabel.frame.origin.x, dateLabel.frame.origin.y, 152, dateLabel.frame.size.height);
    } else {
        warningImageView.hidden = YES;
        actionLabel.frame = CGRectMake(actionLabel.frame.origin.x, actionLabel.frame.origin.y, 172, actionLabel.frame.size.height);
        dateLabel.frame = CGRectMake(dateLabel.frame.origin.x, dateLabel.frame.origin.y, 172, dateLabel.frame.size.height);
    }
    
    if (transaction.confirmations >= kConfirmationThreshold) {
        btcButton.alpha = 1;
        actionLabel.alpha = 1;
    } else {
        btcButton.alpha = 0.5;
        actionLabel.alpha = 0.5;
    }
    
    dateLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:IS_USING_SCREEN_SIZE_LARGER_THAN_5S ? [[NSNumber numberWithFloat:FONT_SIZE_EXTRA_SMALL] longLongValue] - [[NSNumber numberWithFloat:2.0] longLongValue] : FONT_SIZE_EXTRA_SMALL];
    actionLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:IS_USING_SCREEN_SIZE_LARGER_THAN_5S ? [[NSNumber numberWithFloat:FONT_SIZE_MEDIUM_LARGE] longLongValue] - [[NSNumber numberWithFloat:2.0] longLongValue] : FONT_SIZE_MEDIUM_LARGE];
    btcButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size: IS_USING_SCREEN_SIZE_LARGER_THAN_5S ? [[NSNumber numberWithFloat:FONT_SIZE_SMALL_MEDIUM] longLongValue] - [[NSNumber numberWithFloat:3.0] longLongValue] : FONT_SIZE_SMALL_MEDIUM];
    btcButton.titleEdgeInsets = UIEdgeInsetsMake(0, 8, 0, 8);
    
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    
    // Configure the view for the selected state
}

#pragma mark button interactions

- (IBAction)transactionClicked:(UIButton *)button
{
    TransactionDetailViewController *detailViewController = [TransactionDetailViewController new];
    detailViewController.transactionModel = [[TransactionDetailViewModel alloc] initWithTransaction:transaction];
    
    TransactionDetailNavigationController *navigationController = [[TransactionDetailNavigationController alloc] initWithRootViewController:detailViewController];
    navigationController.transactionHash = transaction.myHash;
    
    detailViewController.busyViewDelegate = navigationController;
    navigationController.onDismiss = ^() {
        app.tabControllerManager.transactionsBitcoinViewController.detailViewController = nil;
    };
    navigationController.modalTransitionStyle = UIModalTransitionStyleCoverVertical;
    app.tabControllerManager.transactionsBitcoinViewController.detailViewController = detailViewController;
    
    if (app.topViewControllerDelegate) {
        [app.topViewControllerDelegate presentViewController:navigationController animated:YES completion:nil];
    } else {
        [app.window.rootViewController presentViewController:navigationController animated:YES completion:nil];
    }
}

- (IBAction)btcbuttonclicked:(id)sender
{
    [self transactionClicked:nil];
}

@end
