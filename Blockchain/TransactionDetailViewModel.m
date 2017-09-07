//
//  TransactionDetailViewModel.m
//  Blockchain
//
//  Created by kevinwu on 9/7/17.
//  Copyright © 2017 Blockchain Luxembourg S.A. All rights reserved.
//

#import "TransactionDetailViewModel.h"
#import "ContactTransaction.h"
#import "Transaction.h"
#import "EtherTransaction.h"
#import "NSNumberFormatter+Currencies.h"

@implementation TransactionDetailViewModel

- (id)initWithTransaction:(Transaction *)transaction
{
    if (self == [super init]) {
        self.from = transaction.from;
        self.to = transaction.to;
        self.amount = ABS(transaction.amount);
        self.txType = transaction.txType;
        self.time = transaction.time;
        self.note = transaction.note;
        self.confirmations = transaction.confirmations;
        self.fiatAmountsAtTime = transaction.fiatAmountsAtTime;
        self.doubleSpend = transaction.doubleSpend;
        self.replaceByFee = transaction.replaceByFee;
        self.dateString = [self getDate];
        self.myHash = transaction.myHash;
        self.feeString = [NSNumberFormatter formatMoneyWithLocalSymbol:ABS(transaction.fee)];
        
        if ([transaction isMemberOfClass:[ContactTransaction class]]) {
            ContactTransaction *contactTransaction = (ContactTransaction *)transaction;
            self.isContactTransaction = YES;
            self.reason = contactTransaction.reason;
        };
        self.contactName = transaction.contactName;
    }
    return self;
}

- (id)initWithEtherTransaction:(EtherTransaction *)etherTransaction
{
    if (self == [super init]) {
        
    }
    return self;
}

- (NSString *)getDate
{
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    [dateFormatter setAMSymbol:@"am"];
    [dateFormatter setPMSymbol:@"pm"];
    [dateFormatter setDateFormat:@"MMMM dd, yyyy @ h:mmaa"];
    NSDate *date = [NSDate dateWithTimeIntervalSince1970:self.time];
    NSString *dateString = [dateFormatter stringFromDate:date];
    return dateString;
}

@end
