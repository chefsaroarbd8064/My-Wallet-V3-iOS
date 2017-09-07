//
//  TransactionDetailFromCell.m
//  Blockchain
//
//  Created by Kevin Wu on 9/27/16.
//  Copyright © 2016 Blockchain Luxembourg S.A. All rights reserved.
//

#import "TransactionDetailFromCell.h"
#import "ContactTransaction.h"
#import "UIView+ChangeFrameAttribute.h"

@implementation TransactionDetailFromCell

- (void)prepareForReuse
{
    [super prepareForReuse];
    [self.mainLabel setText:nil];
    [self.accessoryLabel setText:nil];
    [self.accessoryButton setHidden:YES];
}

- (void)configureWithTransactionModel:(TransactionDetailViewModel *)transactionModel
{
    [super configureWithTransactionModel:transactionModel];

    if (self.isSetup) {
        self.mainLabel.text = BC_STRING_FROM;
        self.accessoryLabel.text = [transactionModel.from objectForKey:DICTIONARY_KEY_LABEL];
        return;
    }
    
    self.mainLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 70, 20.5)];
    self.mainLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_MEDIUM_LARGE];
    self.mainLabel.text = BC_STRING_FROM;
    self.mainLabel.textColor = COLOR_TEXT_DARK_GRAY;
    [self.mainLabel sizeToFit];
    [self.mainLabel changeXPosition:self.contentView.layoutMargins.left];
    [self.contentView addSubview:self.mainLabel];
    
    CGFloat accessoryLabelXPosition = self.mainLabel.frame.origin.x + self.mainLabel.frame.size.width + 8;
    self.accessoryLabel = [[UILabel alloc] initWithFrame:CGRectMake(accessoryLabelXPosition, 0, self.frame.size.width - self.contentView.layoutMargins.right - accessoryLabelXPosition, 20.5)];
    self.accessoryLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_EXTRA_EXTRA_SMALL];
    self.accessoryLabel.textColor = COLOR_TEXT_DARK_GRAY;
    self.accessoryLabel.textAlignment = NSTextAlignmentRight;
    self.accessoryLabel.adjustsFontSizeToFitWidth = YES;
    self.accessoryLabel.text = transactionModel.isContactTransaction && [transactionModel.txType isEqualToString:TX_TYPE_RECEIVED] ? transactionModel.contactName : [transactionModel.from objectForKey:DICTIONARY_KEY_LABEL];
    
    CGFloat mainLabelHeight = self.mainLabel.frame.size.height;
    CGFloat accessoryLabelHeight = self.accessoryLabel.frame.size.height;
    
    CGFloat targetHeight = mainLabelHeight > accessoryLabelHeight ? mainLabelHeight : accessoryLabelHeight;
    
    [self.mainLabel changeHeight:targetHeight];
    [self.accessoryLabel changeHeight:targetHeight];
    
    [self.contentView addSubview:self.accessoryLabel];
    
    self.isSetup = YES;
}

@end
