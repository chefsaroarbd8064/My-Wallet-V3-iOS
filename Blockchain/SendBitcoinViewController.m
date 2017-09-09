//
//  SendViewController.m
//  Blockchain
//
//  Created by Ben Reeves on 17/03/2012.
//  Copyright (c) 2012 Blockchain Luxembourg S.A. All rights reserved.
//

#import "SendBitcoinViewController.h"
#import "Wallet.h"
#import "RootService.h"
#import "BCAddressSelectionView.h"
#import "TabViewController.h"
#import "UncaughtExceptionHandler.h"
#import "UITextField+Blocks.h"
#import "UIViewController+AutoDismiss.h"
#import "LocalizationConstants.h"
#import "TransactionsBitcoinViewController.h"
#import "PrivateKeyReader.h"
#import "UIView+ChangeFrameAttribute.h"
#import "TransferAllFundsBuilder.h"
#import "BCContactRequestView.h"
#import "Contact.h"
#import "ContactTransaction.h"
#import "BCNavigationController.h"
#import "BCFeeSelectionView.h"
#import "StoreKit/StoreKit.h"
#import "BCConfirmPaymentViewModel.h"

typedef enum {
    TransactionTypeRegular = 100,
    TransactionTypeSweep = 200,
    TransactionTypeSweepAndConfirm = 300,
} TransactionType;

typedef enum {
    RejectionTypeDecline,
    RejectionTypeCancel
} RejectionType;

@interface SendBitcoinViewController () <UITextFieldDelegate, TransferAllFundsDelegate, FeeSelectionDelegate, ContactRequestDelegate, ConfirmPaymentViewDelegate>

@property (nonatomic) TransactionType transactionType;

@property (nonatomic, readwrite) DestinationAddressSource addressSource;

@property (nonatomic) uint64_t recommendedForcedFee;
@property (nonatomic) uint64_t maxSendableAmount;
@property (nonatomic) uint64_t feeFromTransactionProposal;
@property (nonatomic) uint64_t lastDisplayedFee;
@property (nonatomic) uint64_t dust;
@property (nonatomic) uint64_t txSize;

@property (nonatomic) uint64_t amountFromURLHandler;
@property (nonatomic) ContactTransaction *contactTransaction;

@property (nonatomic) uint64_t upperRecommendedLimit;
@property (nonatomic) uint64_t lowerRecommendedLimit;
@property (nonatomic) uint64_t estimatedTransactionSize;

@property (nonatomic) FeeType feeType;
@property (nonatomic) UILabel *feeTypeLabel;
@property (nonatomic) UILabel *feeDescriptionLabel;
@property (nonatomic) UILabel *feeAmountLabel;
@property (nonatomic) UILabel *feeWarningLabel;
@property (nonatomic) NSDictionary *fees;

@property (nonatomic) NSString *noteToSet;

@property (nonatomic) BOOL isReloading;
@property (nonatomic) BOOL shouldReloadFeeAmountLabel;

@property (nonatomic, copy) void (^getTransactionFeeSuccess)();
@property (nonatomic, copy) void (^getDynamicFeeError)();

@property (nonatomic, copy) void (^onViewDidLoad)();

@property (nonatomic) TransferAllFundsBuilder *transferAllPaymentBuilder;

@property (nonatomic) BCNavigationController *contactRequestNavigationController;

@end

@implementation SendBitcoinViewController

AVCaptureSession *captureSession;
AVCaptureVideoPreviewLayer *videoPreviewLayer;

float containerOffset;

uint64_t amountInSatoshi = 0.0;
uint64_t availableAmount = 0.0;

BOOL displayingLocalSymbolSend;

#pragma mark - Lifecycle

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    CGFloat statusBarAdjustment = [[UIApplication sharedApplication] statusBarFrame].size.height > DEFAULT_STATUS_BAR_HEIGHT ? DEFAULT_STATUS_BAR_HEIGHT : 0;
    
    self.view.frame = CGRectMake(0,
                                 TAB_HEADER_HEIGHT_DEFAULT - TAB_HEADER_HEIGHT_SMALL_OFFSET - DEFAULT_HEADER_HEIGHT,
                                 app.window.frame.size.width,
                                 app.window.frame.size.height - (TAB_HEADER_HEIGHT_DEFAULT - TAB_HEADER_HEIGHT_SMALL_OFFSET) - DEFAULT_FOOTER_HEIGHT - statusBarAdjustment);
    
    [containerView changeWidth:WINDOW_WIDTH];

    [selectAddressTextField changeWidth:self.view.frame.size.width - fromLabel.frame.size.width - 15 - 13 - selectFromButton.frame.size.width];
    [selectFromButton changeXPosition:self.view.frame.size.width - selectFromButton.frame.size.width];
    
    [toField changeWidth:self.view.frame.size.width - toLabel.frame.size.width - 15 - 13 - addressBookButton.frame.size.width];
    [addressBookButton changeXPosition:self.view.frame.size.width - addressBookButton.frame.size.width];
    
    CGFloat amountFieldWidth = (self.view.frame.size.width - btcLabel.frame.origin.x - btcLabel.frame.size.width - fiatLabel.frame.size.width - 15 - 13 - 8 - 13)/2;
    btcAmountField.frame = CGRectMake(btcAmountField.frame.origin.x, btcAmountField.frame.origin.y, amountFieldWidth, btcAmountField.frame.size.height);
    fiatLabel.frame = CGRectMake(btcAmountField.frame.origin.x + btcAmountField.frame.size.width + 8, fiatLabel.frame.origin.y, fiatLabel.frame.size.width, fiatLabel.frame.size.height);
    fiatAmountField.frame = CGRectMake(fiatLabel.frame.origin.x + fiatLabel.frame.size.width + 13, fiatAmountField.frame.origin.y, amountFieldWidth, fiatAmountField.frame.size.height);
    
    [feeOptionsButton changeXPosition:self.view.frame.size.width - feeOptionsButton.frame.size.width];
    
    self.feeDescriptionLabel.frame = CGRectMake(feeField.frame.origin.x, feeField.center.y, btcAmountField.frame.size.width*2/3, 20);
    self.feeDescriptionLabel.adjustsFontSizeToFitWidth = YES;
    self.feeTypeLabel.frame = CGRectMake(feeField.frame.origin.x, feeField.center.y - 20, btcAmountField.frame.size.width*2/3, 20);
    CGFloat amountLabelOriginX = self.feeTypeLabel.frame.origin.x + self.feeTypeLabel.frame.size.width;
    self.feeTypeLabel.adjustsFontSizeToFitWidth = YES;
    self.feeAmountLabel.frame = CGRectMake(amountLabelOriginX, feeField.center.y - 10, feeOptionsButton.frame.origin.x - amountLabelOriginX, 20);
    self.feeAmountLabel.adjustsFontSizeToFitWidth = YES;

    [self setupFeeWarningLabelFrameSmall];
    
    [feeField changeWidth:self.feeAmountLabel.frame.origin.x - (feeLabel.frame.origin.x + feeLabel.frame.size.width) - (feeField.frame.origin.x - (feeLabel.frame.origin.x + feeLabel.frame.size.width))];

    sendProgressModalText.text = nil;
    
    [[NSNotificationCenter defaultCenter] addObserverForName:NOTIFICATION_KEY_LOADING_TEXT object:nil queue:nil usingBlock:^(NSNotification * notification) {
        
        sendProgressModalText.text = [notification object];
    }];
    
    app.mainTitleLabel.text = BC_STRING_SEND;
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NOTIFICATION_KEY_LOADING_TEXT object:nil];
    
    if (self.addressSource == DestinationAddressSourceContact && app.tabControllerManager.tabViewController.selectedIndex != TAB_SEND) [self reload];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    btcAmountField.inputAccessoryView = amountKeyboardAccessoryView;
    fiatAmountField.inputAccessoryView = amountKeyboardAccessoryView;
    toField.inputAccessoryView = amountKeyboardAccessoryView;
    feeField.inputAccessoryView = amountKeyboardAccessoryView;
    
    fromLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL];
    selectAddressTextField.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    toLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL];
    toField.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    btcLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL];
    btcAmountField.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    fiatLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL];
    fiatAmountField.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    feeLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_SMALL];
    feeField.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    
    [self setupFeeLabels];
    
    fundsAvailableButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    [fundsAvailableButton setTitleColor:COLOR_BLOCKCHAIN_LIGHT_BLUE forState:UIControlStateNormal];
    fundsAvailableButton.titleLabel.adjustsFontSizeToFitWidth = YES;
    
    feeField.delegate = self;
        
    toField.placeholder = BC_STRING_ENTER_BITCOIN_ADDRESS_OR_SELECT;
    feeField.placeholder = BC_STRING_SATOSHI_PER_BYTE_ABBREVIATED;
    btcAmountField.placeholder = [NSString stringWithFormat:BTC_PLACEHOLDER_DECIMAL_SEPARATOR_ARGUMENT, [[NSLocale currentLocale] objectForKey:NSLocaleDecimalSeparator]];
    fiatAmountField.placeholder = [NSString stringWithFormat:FIAT_PLACEHOLDER_DECIMAL_SEPARATOR_ARGUMENT, [[NSLocale currentLocale] objectForKey:NSLocaleDecimalSeparator]];

    toField.clearButtonMode = UITextFieldViewModeWhileEditing;
    [toField setReturnKeyType:UIReturnKeyDone];
    
    CGFloat continueButtonOriginY = [self continuePaymentButtonOriginY];
    continuePaymentButton.frame = CGRectMake(0, continueButtonOriginY, self.view.frame.size.width - 40, BUTTON_HEIGHT);
    continuePaymentButton.center = CGPointMake(self.view.center.x, continuePaymentButton.center.y);
    
    rejectPaymentButton.titleLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:17.0];
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(feeOptionsClicked:)];
    [feeTappableView addGestureRecognizer:tapGestureRecognizer];
    
    [self reload];
    
    if (self.onViewDidLoad) {
        self.onViewDidLoad();
        self.onViewDidLoad = nil;
    }
}

- (void)setupFeeLabels
{
    self.feeDescriptionLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.feeDescriptionLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    self.feeDescriptionLabel.textColor = COLOR_LIGHT_GRAY;
    [bottomContainerView addSubview:self.feeDescriptionLabel];
    
    self.feeTypeLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.feeTypeLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    self.feeTypeLabel.textColor = COLOR_TEXT_DARK_GRAY;
    [bottomContainerView addSubview:self.feeTypeLabel];
    
    self.feeAmountLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    self.feeAmountLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    self.feeAmountLabel.textColor = COLOR_TEXT_DARK_GRAY;
    [bottomContainerView addSubview:self.feeAmountLabel];
    
    self.feeWarningLabel = [[UILabel alloc] initWithFrame:CGRectZero];
    // Use same font size for all screen sizes
    self.feeWarningLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_REGULAR size:FONT_SIZE_EXTRA_SMALL];
    self.feeWarningLabel.textColor = COLOR_WARNING_RED;
    self.feeWarningLabel.numberOfLines = 2;
    [bottomContainerView addSubview:self.feeWarningLabel];
}

- (void)resetPayment
{
    self.surgeIsOccurring = NO;
    self.dust = 0;
    
    self.contactTransaction = nil;
    
    [app.wallet createNewBitcoinPayment];
    [self resetFromAddress];
    if (app.tabControllerManager.tabViewController.activeViewController == self) {
        [app closeModalWithTransition:kCATransitionPush];
    }
    
    self.transactionType = TransactionTypeRegular;
}

- (void)resetFromAddress
{
    self.fromAddress = @"";
    if ([app.wallet hasAccount]) {
        // Default setting: send from default account
        self.sendFromAddress = false;
        int defaultAccountIndex = [app.wallet getFilteredOrDefaultAccountIndex];
        self.fromAccount = defaultAccountIndex;
        if (self.isReloading) return; // didSelectFromAccount will be called in reloadAfterMultiAddressResponse
        [self didSelectFromAccount:self.fromAccount];
    }
    else {
        // Default setting: send from any address
        self.sendFromAddress = true;
        if (self.isReloading) return; // didSelectFromAddress will be called in reloadAfterMultiAddressResponse
        [self didSelectFromAddress:self.fromAddress];
    }
}

- (void)clearToAddressAndAmountFields
{
    self.toAddress = @"";
    toField.text = @"";
    amountInSatoshi = 0;
    btcAmountField.text = @"";
    fiatAmountField.text = @"";
    feeField.text = @"";
}

- (void)reload
{
    self.isReloading = YES;
    
    [self clearToAddressAndAmountFields];

    if (![app.wallet isInitialized]) {
        DLog(@"SendViewController: Wallet not initialized");
        return;
    }
    
    if (!app.latestResponse) {
        DLog(@"SendViewController: No latest response");
        return;
    }
    
    [self resetPayment];
    
    // Default: send to address
    self.sendToAddress = true;
    
    [self hideSelectFromAndToButtonsIfAppropriate];
    
    [self populateFieldsFromURLHandlerIfAvailable];
    
    [self reloadFromAndToFields];
    
    [self reloadSymbols];
    
    [self updateFundsAvailable];
    
    [self enablePaymentButtons];
    
    [self setupFees];
    
    sendProgressCancelButton.hidden = YES;
    
    [self enableAmountViews];
    [self enableToField];
    [self hideContactLabel];

    [self hideRejectPaymentButton];
    
    self.isSending = NO;
    self.isReloading = NO;
    
    self.noteToSet = nil;
}

- (void)reloadAfterMultiAddressResponse
{
    [self hideSelectFromAndToButtonsIfAppropriate];
    
    [self reloadLocalAndBtcSymbolsFromLatestResponse];
    
    if (self.sendFromAddress) {
        [app.wallet changePaymentFromAddress:self.fromAddress isAdvanced:self.feeType == FeeTypeCustom];
    } else {
        [app.wallet changePaymentFromAccount:self.fromAccount isAdvanced:self.feeType == FeeTypeCustom];
    }
    
    if (self.shouldReloadFeeAmountLabel) {
        self.shouldReloadFeeAmountLabel = NO;
        if (self.feeAmountLabel.text) {
            [self updateFeeAmountLabelText:self.lastDisplayedFee];
        }
    }
}

- (void)reloadFeeAmountLabel
{
    self.shouldReloadFeeAmountLabel = YES;
}

- (void)reloadSymbols
{
    [self reloadLocalAndBtcSymbolsFromLatestResponse];
    [self updateFundsAvailable];
}

- (void)hideSelectFromAndToButtonsIfAppropriate
{
    // If we only have one account and no legacy addresses -> can't change from address
    if ([app.wallet getActiveAccountsCount] + [[app.wallet activeLegacyAddresses] count] == 1) {
        
        [selectFromButton setHidden:YES];
        
        if ([app.wallet addressBook].count == 0 && [[app.wallet.contacts allValues] count] == 0) {
            [addressBookButton setHidden:YES];
        } else {
            [addressBookButton setHidden:NO];
        }
    }
    else {
        [selectFromButton setHidden:NO];
        [addressBookButton setHidden:NO];
    }
}

- (void)populateFieldsFromURLHandlerIfAvailable
{
    if (self.addressFromURLHandler && toField != nil) {
        self.sendToAddress = true;
        self.toAddress = self.addressFromURLHandler;
        DLog(@"toAddress: %@", self.toAddress);
        
        toField.text = [self labelForLegacyAddress:self.toAddress];
        self.addressFromURLHandler = nil;
        
        amountInSatoshi = self.amountFromURLHandler;
        [self performSelector:@selector(doCurrencyConversion) withObject:nil afterDelay:0.1f];
        self.amountFromURLHandler = 0;
    }
}

- (void)showContactLabelWithName:(NSString *)name reason:(NSString *)reason
{
    CGFloat originX = toField.frame.origin.x;
    CGFloat originY = lineBelowFromField.frame.origin.y + 4;
    contactLabel.frame = CGRectMake(originX, originY, addressBookButton.frame.origin.x - originX, lineBelowToField.frame.origin.y - originY - 4);
    contactLabel.font = [UIFont fontWithName:FONT_MONTSERRAT_LIGHT size:FONT_SIZE_SMALL];
    contactLabel.textColor = COLOR_TEXT_DARK_GRAY;
    
    contactLabel.hidden = NO;
    contactLabel.text = IS_USING_SCREEN_SIZE_4S ? [NSString stringWithFormat:@"%@ - %@", name, reason] : [NSString stringWithFormat:@"%@\n%@", name, reason];
    contactLabel.alpha = 0.5;
}

- (void)reloadFromAndToFields
{
    [self reloadFromField];
    [self reloadToField];
}

- (void)reloadFromField
{
    if (self.sendFromAddress) {
        if (self.fromAddress.length == 0) {
            selectAddressTextField.text = BC_STRING_ANY_ADDRESS;
            availableAmount = [app.wallet getTotalBalanceForSpendableActiveLegacyAddresses];
        }
        else {
            selectAddressTextField.text = [self labelForLegacyAddress:self.fromAddress];
            availableAmount = [app.wallet getLegacyAddressBalance:self.fromAddress];
        }
    }
    else {
        selectAddressTextField.text = [app.wallet getLabelForAccount:self.fromAccount];
        availableAmount = [app.wallet getBalanceForAccount:self.fromAccount];
    }
}

- (void)reloadToField
{
    self.toContact = nil;
    
    if (self.sendToAddress) {
        toField.text = [self labelForLegacyAddress:self.toAddress];
        if ([app.wallet isBitcoinAddress:self.toAddress]) {
            [self selectToAddress:self.toAddress];
        } else {
            toField.text = @"";
            self.toAddress = @"";
        }
    }
    else {
        toField.text = [app.wallet getLabelForAccount:self.toAccount];
        [self selectToAccount:self.toAccount];
    }
}

- (void)reloadLocalAndBtcSymbolsFromLatestResponse
{
    if (app.latestResponse.symbol_local && app.latestResponse.symbol_btc) {
        fiatLabel.text = app.latestResponse.symbol_local.code;
        btcLabel.text = app.latestResponse.symbol_btc.symbol;
    }
    
    if (app->symbolLocal && app.latestResponse.symbol_local && app.latestResponse.symbol_local.conversion > 0) {
        displayingLocalSymbol = TRUE;
        displayingLocalSymbolSend = TRUE;
    } else if (app.latestResponse.symbol_btc) {
        displayingLocalSymbol = FALSE;
        displayingLocalSymbolSend = FALSE;
    }
}

#pragma mark - Payment

- (IBAction)reallyDoPayment:(id)sender
{
    if (self.sendFromAddress && [app.wallet isWatchOnlyLegacyAddress:self.fromAddress]) {
        
        [self alertUserForSpendingFromWatchOnlyAddress];
    
        return;
    } else {
        [self sendPaymentWithListener];
    }
}

- (void)getInfoForTransferAllFundsToDefaultAccount
{
    app.topViewControllerDelegate = nil;
    
    [app showBusyViewWithLoadingText:BC_STRING_TRANSFER_ALL_PREPARING_TRANSFER];
    
    [app.wallet getInfoForTransferAllFundsToAccount];
}

- (void)transferFundsToDefaultAccountFromAddress:(NSString *)address
{
    [self didSelectFromAddress:address];
    
    [self selectToAccount:[app.wallet getDefaultAccountIndex]];
    
    [app.wallet transferFundsToDefaultAccountFromAddress:address];
}

- (void)sendFromWatchOnlyAddress
{
    [self sendPaymentWithListener];
}

- (void)sendPaymentWithListener
{
    [self disablePaymentButtons];
    
    [sendProgressActivityIndicator startAnimating];
    
    sendProgressModalText.text = BC_STRING_SENDING_TRANSACTION;
    
    [app showModalWithContent:sendProgressModal closeType:ModalCloseTypeNone headerText:BC_STRING_SENDING_TRANSACTION];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        transactionProgressListeners *listener = [[transactionProgressListeners alloc] init];
         
         listener.on_start = ^() {
         };
         
         listener.on_begin_signing = ^() {
             sendProgressModalText.text = BC_STRING_SIGNING_INPUTS;
         };
         
         listener.on_sign_progress = ^(int input) {
             DLog(@"Signing input: %d", input);
             sendProgressModalText.text = [NSString stringWithFormat:BC_STRING_SIGNING_INPUT, input];
         };
         
         listener.on_finish_signing = ^() {
             sendProgressModalText.text = BC_STRING_FINISHED_SIGNING_INPUTS;
         };
         
         listener.on_success = ^(NSString*secondPassword, NSString *transactionHash) {
             
             DLog(@"SendViewController: on_success");
             
             UIAlertController *paymentSentAlert = [UIAlertController alertControllerWithTitle:BC_STRING_SUCCESS message:BC_STRING_PAYMENT_SENT preferredStyle:UIAlertControllerStyleAlert];
             [paymentSentAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                 if (![[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_HIDE_APP_REVIEW_PROMPT]) {
                     
                     if ([app.wallet getAllTransactionsCount] < NUMBER_OF_TRANSACTIONS_REQUIRED_FOR_FOR_APP_STORE_REVIEW_PROMPT) {
                         return;
                     }
                     
                     id promptDate = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_KEY_APP_REVIEW_PROMPT_DATE];
                     
                     if (promptDate) {
                         NSTimeInterval secondsSincePrompt = [[NSDate date] timeIntervalSinceDate:promptDate];
                         NSTimeInterval secondsUntilPromptingAgain = TIME_INTERVAL_APP_STORE_REVIEW_PROMPT;
#ifdef ENABLE_DEBUG_MENU
                         id customTimeValue = [[NSUserDefaults standardUserDefaults] objectForKey:USER_DEFAULTS_KEY_DEBUG_APP_REVIEW_PROMPT_CUSTOM_TIMER];
                         if (customTimeValue) {
                             secondsUntilPromptingAgain = [customTimeValue doubleValue];
                         }
#endif
                         if (secondsSincePrompt < secondsUntilPromptingAgain) {
                             return;
                         }
                     }
                     
                     if (NSClassFromString(@"SKStoreReviewController") && [SKStoreReviewController respondsToSelector:@selector(requestReview)]) {
                         [SKStoreReviewController requestReview];
                         [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:USER_DEFAULTS_KEY_APP_REVIEW_PROMPT_DATE];
                     } else {
                         UIAlertController *appReviewAlert = [UIAlertController alertControllerWithTitle:BC_STRING_APP_REVIEW_PROMPT_TITLE message:BC_STRING_APP_REVIEW_PROMPT_MESSAGE preferredStyle:UIAlertControllerStyleAlert];
                         [appReviewAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_YES_RATE_BLOCKCHAIN_WALLET style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                             [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_HIDE_APP_REVIEW_PROMPT];
                             [app rateApp];
                         }]];
                         [appReviewAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_ASK_ME_LATER style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                             [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:USER_DEFAULTS_KEY_APP_REVIEW_PROMPT_DATE];
                         }]];
                         [appReviewAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_DONT_SHOW_AGAIN style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                             [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_HIDE_APP_REVIEW_PROMPT];
                         }]];

                         [app.window.rootViewController presentViewController:appReviewAlert animated:YES completion:nil];
                     }
                 }
             }]];
             
             [app.window.rootViewController presentViewController:paymentSentAlert animated:YES completion:nil];
             
             [sendProgressActivityIndicator stopAnimating];
             
             [self enablePaymentButtons];
             
             // Fields are automatically reset by reload, called by MyWallet.wallet.getHistory() after a utx websocket message is received. However, we cannot rely on the websocket 100% of the time.
             [app.wallet performSelector:@selector(getHistoryIfNoTransactionMessage) withObject:nil afterDelay:DELAY_GET_HISTORY_BACKUP];
             
             // Close transaction modal, go to transactions view, scroll to top and animate new transaction
             [app closeModalWithTransition:kCATransitionFade];
             [app.tabControllerManager.transactionsBitcoinViewController didReceiveTransactionMessage];
             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                 [app.tabControllerManager transactionsClicked:nil];
             });
             dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                 [app.tabControllerManager.transactionsBitcoinViewController.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
             });
             
             if (self.noteToSet) {
                 [app.wallet saveNote:self.noteToSet forTransaction:transactionHash];
             }
             
             [self reload];
         };
         
         listener.on_error = ^(NSString* error, NSString* secondPassword) {
             DLog(@"Send error: %@", error);
                          
             if ([error isEqualToString:ERROR_UNDEFINED]) {
                 [app standardNotify:BC_STRING_SEND_ERROR_NO_INTERNET_CONNECTION];
             } else if ([error isEqualToString:ERROR_FEE_TOO_LOW]) {
                 [app standardNotify:BC_STRING_SEND_ERROR_FEE_TOO_LOW];
             } else if ([error isEqualToString:ERROR_FAILED_NETWORK_REQUEST]) {
                 [app standardNotify:BC_STRING_REQUEST_FAILED_PLEASE_CHECK_INTERNET_CONNECTION];
             } else if (error && error.length != 0)  {
                 [app standardNotify:error];
             }
             
             [sendProgressActivityIndicator stopAnimating];
             
             [self enablePaymentButtons];
             
             [app closeModalWithTransition:kCATransitionFade];
             
             [self reload];
             
             [app.wallet getHistory];
         };
         
         NSString *amountString;
         amountString = [[NSNumber numberWithLongLong:amountInSatoshi] stringValue];
         
         DLog(@"Sending uint64_t %llu Satoshi (String value: %@)", amountInSatoshi, amountString);
         
         // Different ways of sending (from/to address or account
         if (self.sendFromAddress && self.sendToAddress) {
             DLog(@"From: %@", self.fromAddress);
             DLog(@"To: %@", self.toAddress);
         }
         else if (self.sendFromAddress && !self.sendToAddress) {
             DLog(@"From: %@", self.fromAddress);
             DLog(@"To account: %d", self.toAccount);
         }
         else if (!self.sendFromAddress && self.sendToAddress) {
             DLog(@"From account: %d", self.fromAccount);
             DLog(@"To: %@", self.toAddress);
         }
         else if (!self.sendFromAddress && !self.sendToAddress) {
             DLog(@"From account: %d", self.fromAccount);
             DLog(@"To account: %d", self.toAccount);
         }
         
         app.wallet.didReceiveMessageForLastTransaction = NO;
         
         [app.wallet sendPaymentWithListener:listener secondPassword:nil];
    });
}

- (void)transferAllFundsToDefaultAccount
{
    __weak SendBitcoinViewController *weakSelf = self;
    
    self.transferAllPaymentBuilder.on_before_send = ^() {
        
        SendBitcoinViewController *strongSelf = weakSelf;
        
        [weakSelf hideKeyboard];
        
        [weakSelf disablePaymentButtons];
        
        [strongSelf->sendProgressActivityIndicator startAnimating];
        
        if (weakSelf.transferAllPaymentBuilder.transferAllAddressesInitialCount - [weakSelf.transferAllPaymentBuilder.transferAllAddressesToTransfer count] <= weakSelf.transferAllPaymentBuilder.transferAllAddressesInitialCount) {
            strongSelf->sendProgressModalText.text = [NSString stringWithFormat:BC_STRING_TRANSFER_ALL_FROM_ADDRESS_ARGUMENT_ARGUMENT, weakSelf.transferAllPaymentBuilder.transferAllAddressesInitialCount - [weakSelf.transferAllPaymentBuilder.transferAllAddressesToTransfer count] + 1, weakSelf.transferAllPaymentBuilder.transferAllAddressesInitialCount];
        }
        
        [app showModalWithContent:strongSelf->sendProgressModal closeType:ModalCloseTypeNone headerText:BC_STRING_SENDING_TRANSACTION];
        
        [UIView animateWithDuration:0.3f animations:^{
            UIButton *cancelButton = strongSelf->sendProgressCancelButton;
            strongSelf->sendProgressCancelButton.frame = CGRectMake(0, self.view.frame.size.height + DEFAULT_FOOTER_HEIGHT - cancelButton.frame.size.height, cancelButton.frame.size.width, cancelButton.frame.size.height);
        }];
        
        weakSelf.isSending = YES;
    };
    
    self.transferAllPaymentBuilder.on_prepare_next_transfer = ^(NSArray *transferAllAddressesToTransfer) {
        weakSelf.fromAddress = transferAllAddressesToTransfer[0];
    };
    
    self.transferAllPaymentBuilder.on_success = ^(NSString *secondPassword) {
        
    };
    
    self.transferAllPaymentBuilder.on_error = ^(NSString *error, NSString *secondPassword) {
        
        SendBitcoinViewController *strongSelf = weakSelf;

        [app closeAllModals];

        [strongSelf->sendProgressActivityIndicator stopAnimating];
        
        [weakSelf enablePaymentButtons];
        
        [weakSelf reload];
    };

    [self.transferAllPaymentBuilder transferAllFundsToAccountWithSecondPassword:nil];
}

- (void)didFinishTransferFunds:(NSString *)summary
{
    NSString *message = [self.transferAllPaymentBuilder.transferAllAddressesTransferred count] > 0 ? [NSString stringWithFormat:@"%@\n\n%@", summary, BC_STRING_PAYMENT_ASK_TO_ARCHIVE_TRANSFERRED_ADDRESSES] : summary;
    
    UIAlertController *alertForPaymentsSent = [UIAlertController alertControllerWithTitle:BC_STRING_PAYMENTS_SENT message:message preferredStyle:UIAlertControllerStyleAlert];
    
    if ([self.transferAllPaymentBuilder.transferAllAddressesTransferred count] > 0) {
        [alertForPaymentsSent addAction:[UIAlertAction actionWithTitle:BC_STRING_ARCHIVE style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
            [self archiveTransferredAddresses];
        }]];
        [alertForPaymentsSent addAction:[UIAlertAction actionWithTitle:BC_STRING_NOT_NOW style:UIAlertActionStyleCancel handler:nil]];
    } else {
        [alertForPaymentsSent addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:nil]];
    }
    
    [app.tabControllerManager.tabViewController presentViewController:alertForPaymentsSent animated:YES completion:nil];
    
    [sendProgressActivityIndicator stopAnimating];
    
    [self enablePaymentButtons];
    
    // Fields are automatically reset by reload, called by MyWallet.wallet.getHistory() after a utx websocket message is received. However, we cannot rely on the websocket 100% of the time.
    [app.wallet performSelector:@selector(getHistoryIfNoTransactionMessage) withObject:nil afterDelay:DELAY_GET_HISTORY_BACKUP];
    
    // Close transaction modal, go to transactions view, scroll to top and animate new transaction
    [app closeAllModals];
    [app.tabControllerManager.transactionsBitcoinViewController didReceiveTransactionMessage];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [app.tabControllerManager transactionsClicked:nil];
    });
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [app.tabControllerManager.transactionsBitcoinViewController.tableView scrollRectToVisible:CGRectMake(0, 0, 1, 1) animated:NO];
    });
    
    [self reload];
}

- (void)sendDuringTransferAll:(NSString *)secondPassword
{
    [self.transferAllPaymentBuilder transferAllFundsToAccountWithSecondPassword:secondPassword];
}

- (void)didErrorDuringTransferAll:(NSString *)error secondPassword:(NSString *)secondPassword
{
    [app closeAllModals];
    [self reload];
    
    [self showErrorBeforeSending:error];
}

- (void)showSummary
{
    [self showSummaryForTransferAllWithCustomFromLabel:nil];
}

- (void)showSummaryForTransferAllWithCustomFromLabel:(NSString *)customFromLabel
{
    [self hideKeyboard];
    
    // Timeout so the keyboard is fully dismised - otherwise the second password modal keyboard shows the send screen kebyoard accessory
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        
        if ([self transferAllMode] || self.addressSource == DestinationAddressSourceContact) {
            [app.modalView.backButton addTarget:self action:@selector(reload) forControlEvents:UIControlEventTouchUpInside];
        }
        
        uint64_t amountTotal = amountInSatoshi + self.feeFromTransactionProposal + self.dust;
        uint64_t feeTotal = self.dust + self.feeFromTransactionProposal;
        
        NSString *fromAddressLabel = self.sendFromAddress ? [self labelForLegacyAddress:self.fromAddress] : [app.wallet getLabelForAccount:self.fromAccount];
        
        NSString *fromAddressString = self.sendFromAddress ? self.fromAddress : @"";
        
        if ([self.fromAddress isEqualToString:@""] && self.sendFromAddress) {
            fromAddressString = BC_STRING_ANY_ADDRESS;
        }
        
        // When a legacy wallet has no label, labelForLegacyAddress returns the address, so remove the string
        if ([fromAddressLabel isEqualToString:fromAddressString]) {
            fromAddressLabel = @"";
        }
        
        if (customFromLabel) {
            fromAddressString = customFromLabel;
        }
        
        NSString *toAddressLabel = self.sendToAddress ? [self labelForLegacyAddress:self.toAddress] : [app.wallet getLabelForAccount:self.toAccount];
        
        BOOL shouldRemoveToAddress = NO;
        NSString *contactName = self.contactTransaction.contactName;
        shouldRemoveToAddress = contactName && ![contactName isEqualToString:@""];
        
        NSString *toAddressString = self.sendToAddress ? (shouldRemoveToAddress ? @"" : self.toAddress) : @"";
        
        // When a legacy wallet has no label, labelForLegacyAddress returns the address, so remove the string
        if ([toAddressLabel isEqualToString:toAddressString]) {
            toAddressLabel = @"";
        }
        
        NSString *from = fromAddressLabel.length == 0 ? fromAddressString : fromAddressLabel;
        NSString *to = toAddressLabel.length == 0 ? toAddressString : toAddressLabel;
        
        BOOL surgePresent = self.surgeIsOccurring || [[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_DEBUG_SIMULATE_SURGE];
        
        BCConfirmPaymentViewModel *confirmPaymentViewModel = [[BCConfirmPaymentViewModel alloc] initWithFrom:from
                                                                            To:to
                                                                        amount:amountInSatoshi
                                                                           fee:feeTotal
                                                                         total:amountTotal
                                                            contactTransaction:self.contactTransaction
                                                                         surge:surgePresent];
        
        self.confirmPaymentView = [[BCConfirmPaymentView alloc] initWithWindow:app.window viewModel:confirmPaymentViewModel];
        
        self.confirmPaymentView.confirmDelegate = self;
        
        if (customFromLabel) {
            [self.confirmPaymentView.reallyDoPaymentButton addTarget:self action:@selector(transferAllFundsToDefaultAccount) forControlEvents:UIControlEventTouchUpInside];
        } else {
            [self.confirmPaymentView.reallyDoPaymentButton addTarget:self action:@selector(reallyDoPayment:) forControlEvents:UIControlEventTouchUpInside];
        }
        
        [app showModalWithContent:self.confirmPaymentView closeType:ModalCloseTypeBack headerText:BC_STRING_CONFIRM_PAYMENT onDismiss:^{
            [self enablePaymentButtons];
        } onResume:nil];
        
        NSDecimalNumber *last = [NSDecimalNumber decimalNumberWithDecimal:[[NSDecimalNumber numberWithDouble:[[app.wallet.currencySymbols objectForKey:DICTIONARY_KEY_USD][DICTIONARY_KEY_LAST] doubleValue]] decimalValue]];
        NSDecimalNumber *conversionToUSD = [[NSDecimalNumber decimalNumberWithDecimal:[[NSDecimalNumber numberWithDouble:SATOSHI] decimalValue]] decimalNumberByDividingBy:last];
        NSDecimalNumber *feeConvertedToUSD = [(NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:feeTotal] decimalNumberByDividingBy:conversionToUSD];
        
        NSDecimalNumber *feeRatio = [[NSDecimalNumber decimalNumberWithDecimal:[[NSDecimalNumber numberWithLongLong:feeTotal] decimalValue] ] decimalNumberByDividingBy:(NSDecimalNumber *)[NSDecimalNumber numberWithLongLong:amountTotal]];
        NSDecimalNumber *normalFeeRatio = [NSDecimalNumber decimalNumberWithDecimal:[ONE_PERCENT_DECIMAL decimalValue]];
        
        if ([feeConvertedToUSD compare:[NSDecimalNumber decimalNumberWithDecimal:[FIFTY_CENTS_DECIMAL decimalValue]]] == NSOrderedDescending && self.txSize > TX_SIZE_ONE_KILOBYTE && [feeRatio compare:normalFeeRatio] == NSOrderedDescending) {
            UIAlertController *highFeeAlert = [UIAlertController alertControllerWithTitle:BC_STRING_HIGH_FEE_WARNING_TITLE message:BC_STRING_HIGH_FEE_WARNING_MESSAGE preferredStyle:UIAlertControllerStyleAlert];
            [highFeeAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:nil]];
            [self.view.window.rootViewController presentViewController:highFeeAlert animated:YES completion:nil];
        }
    });
}

- (void)handleZeroSpendableAmount
{
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:BC_STRING_NO_AVAILABLE_FUNDS message:BC_STRING_PLEASE_SELECT_DIFFERENT_ADDRESS preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:nil]];
    [[NSNotificationCenter defaultCenter] addObserver:alert selector:@selector(autoDismiss) name:NOTIFICATION_KEY_RELOAD_TO_DISMISS_VIEWS object:nil];
    [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
    [self enablePaymentButtons];
}

- (IBAction)sendProgressCancelButtonClicked:(UIButton *)sender
{
    sendProgressModalText.text = BC_STRING_CANCELLING;
    self.transferAllPaymentBuilder.userCancelledNext = YES;
    [self performSelector:@selector(cancelAndReloadIfTransferFails) withObject:nil afterDelay:10.0];
}

- (void)cancelAndReloadIfTransferFails
{
    if (self.isSending && [sendProgressModalText.text isEqualToString:BC_STRING_CANCELLING]) {
        [self reload];
        [app closeAllModals];
    }
}

#pragma mark - UI Helpers

- (void)doCurrencyConversion
{
    [self doCurrencyConversionAfterMultiAddress:NO];
}

- (void)doCurrencyConversionAfterMultiAddress
{
    [self doCurrencyConversionAfterMultiAddress:YES];
}

- (void)doCurrencyConversionAfterMultiAddress:(BOOL)afterMultiAddress
{
    // If the amount entered exceeds amount available, change the color of the amount text
    if (amountInSatoshi > availableAmount || amountInSatoshi > BTC_LIMIT_IN_SATOSHI) {
        [self highlightInvalidAmounts];
        [self disablePaymentButtons];
    }
    else {
        [self removeHighlightFromAmounts];
        [self enablePaymentButtons];
        if (!afterMultiAddress) {
            [app.wallet changePaymentAmount:amountInSatoshi];
            [self updateSatoshiPerByteWithUpdateType:FeeUpdateTypeNoAction];
        }
    }
    
    if ([btcAmountField isFirstResponder]) {
        fiatAmountField.text = [NSNumberFormatter formatAmount:amountInSatoshi localCurrency:YES];
    }
    else if ([fiatAmountField isFirstResponder]) {
        btcAmountField.text = [NSNumberFormatter formatAmount:amountInSatoshi localCurrency:NO];
    }
    else {
        fiatAmountField.text = [NSNumberFormatter formatAmount:amountInSatoshi localCurrency:YES];
        btcAmountField.text = [NSNumberFormatter formatAmount:amountInSatoshi localCurrency:NO];
    }
    
    [self updateFundsAvailable];
}

- (void)highlightInvalidAmounts
{
    btcAmountField.textColor = COLOR_WARNING_RED;
    fiatAmountField.textColor = COLOR_WARNING_RED;
}

- (void)removeHighlightFromAmounts
{
    btcAmountField.textColor = COLOR_TEXT_DARK_GRAY;
    fiatAmountField.textColor = COLOR_TEXT_DARK_GRAY;
}

- (void)disablePaymentButtons
{
    continuePaymentButton.enabled = NO;
    [continuePaymentButton setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    [continuePaymentButton setBackgroundColor:COLOR_BUTTON_KEYPAD_GRAY];
    
    continuePaymentAccessoryButton.enabled = NO;
    [continuePaymentAccessoryButton setTitleColor:[UIColor grayColor] forState:UIControlStateDisabled];
    [continuePaymentAccessoryButton setBackgroundColor:COLOR_BUTTON_KEYPAD_GRAY];
}

- (void)enablePaymentButtons
{
    continuePaymentButton.enabled = YES;
    [continuePaymentButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [continuePaymentButton setBackgroundColor:COLOR_BLOCKCHAIN_LIGHT_BLUE];
    
    [continuePaymentAccessoryButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    continuePaymentAccessoryButton.enabled = YES;
    [continuePaymentAccessoryButton setBackgroundColor:COLOR_BLOCKCHAIN_LIGHT_BLUE];
}

- (void)setupPaymentRequest:(ContactTransaction *)transaction
{
    int fromAccount = [app.wallet getDefaultAccountIndex];
    
    self.addressFromURLHandler = transaction.address;
    self.amountFromURLHandler = transaction.intendedAmount;
    
    RejectionType rejectionType = [transaction.role isEqualToString:TRANSACTION_ROLE_RPR_INITIATOR] ? RejectionTypeCancel : RejectionTypeDecline;
    
    self.addressSource = DestinationAddressSourceContact;
    
    __weak SendBitcoinViewController *weakSelf = self;
    
    self.onViewDidLoad = ^(){
        weakSelf.contactTransaction = transaction;
        [weakSelf selectFromAccount:fromAccount];
        [weakSelf disableToField];
        [weakSelf disableAmountViews];
        [weakSelf showRejectPaymentButtonWithRejectionType:rejectionType];
        [weakSelf showContactLabelWithName:transaction.contactName reason:transaction.reason];
    };
    
    // Call the getter for self.view to invoke viewDidLoad so that reload is called only once
    if (self.view) {
        // If onViewDidLoad block still exists, viewDidLoad was not called, so reload was not called.
        if (self.onViewDidLoad) {
            self.onViewDidLoad = nil;
            [self reload];
            self.contactTransaction = transaction;
            [self selectFromAccount:fromAccount];
            [self disableToField];
            [self disableAmountViews];
            [self showRejectPaymentButtonWithRejectionType:rejectionType];
            [self showContactLabelWithName:transaction.contactName reason:transaction.reason];
        }
    }
}

- (void)showInsufficientFunds
{
    [self highlightInvalidAmounts];
}

- (void)setAmountStringFromUrlHandler:(NSString*)amountString withToAddress:(NSString*)addressString
{
    self.addressFromURLHandler = addressString;
    
    if ([NSNumberFormatter stringHasBitcoinValue:amountString]) {
        NSDecimalNumber *amountDecimalNumber = [NSDecimalNumber decimalNumberWithString:amountString];
        self.amountFromURLHandler = [[amountDecimalNumber decimalNumberByMultiplyingBy:(NSDecimalNumber *)[NSDecimalNumber numberWithDouble:SATOSHI]] longLongValue];
    } else {
        self.amountFromURLHandler = 0;
    }
    
    self.addressSource = DestinationAddressSourceURI;
}

- (NSString *)labelForLegacyAddress:(NSString *)address
{
    if ([[app.wallet.addressBook objectForKey:address] length] > 0) {
        return [app.wallet.addressBook objectForKey:address];
        
    }
    else if ([app.wallet.allLegacyAddresses containsObject:address]) {
        NSString *label = [app.wallet labelForLegacyAddress:address];
        if (label && ![label isEqualToString:@""])
            return label;
    } else if (self.contactTransaction) {
        NSString *name = self.contactTransaction.contactName;
        if (name && ![name isEqualToString:@""]) return name;
    }
    
    return address;
}

- (void)hideKeyboardForced
{
    // When backgrounding the app quickly, the input accessory view can remain visible without a first responder, so force the keyboard to appear before dismissing it
    [fiatAmountField becomeFirstResponder];
    [self hideKeyboard];
}

- (void)hideKeyboard
{
    [btcAmountField resignFirstResponder];
    [fiatAmountField resignFirstResponder];
    [toField resignFirstResponder];
    [feeField resignFirstResponder];
    
    [self.view removeGestureRecognizer:self.tapGesture];
    self.tapGesture = nil;
}

- (BOOL)isKeyboardVisible
{
    if ([btcAmountField isFirstResponder] || [fiatAmountField isFirstResponder] || [toField isFirstResponder] || [feeField isFirstResponder]) {
        return YES;
    }
    
    return NO;
}

- (void)showErrorBeforeSending:(NSString *)error
{
    if ([self isKeyboardVisible]) {
        [self hideKeyboard];
        [app performSelector:@selector(standardNotifyAutoDismissingController:) withObject:error afterDelay:DELAY_KEYBOARD_DISMISSAL];
    } else {
        [app standardNotifyAutoDismissingController:error];
    }
}

- (void)alertUserForSpendingFromWatchOnlyAddress
{
    UIAlertController *alertForSpendingFromWatchOnly = [UIAlertController alertControllerWithTitle:BC_STRING_PRIVATE_KEY_NEEDED message:[NSString stringWithFormat:BC_STRING_PRIVATE_KEY_NEEDED_MESSAGE_ARGUMENT, self.fromAddress] preferredStyle:UIAlertControllerStyleAlert];
    [alertForSpendingFromWatchOnly addAction:[UIAlertAction actionWithTitle:BC_STRING_CONTINUE style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self scanPrivateKeyToSendFromWatchOnlyAddress];
    }]];
    [alertForSpendingFromWatchOnly addAction:[UIAlertAction actionWithTitle:BC_STRING_CANCEL style:UIAlertActionStyleCancel handler:nil]];
    [app.tabControllerManager.tabViewController presentViewController:alertForSpendingFromWatchOnly animated:YES completion:nil];
}

- (void)scanPrivateKeyToSendFromWatchOnlyAddress
{
    if (![app getCaptureDeviceInput:nil]) {
        return;
    }
    
    PrivateKeyReader *privateKeyScanner = [[PrivateKeyReader alloc] initWithSuccess:^(NSString *privateKeyString) {
        [app.wallet sendFromWatchOnlyAddress:self.fromAddress privateKey:privateKeyString];
    } error:^(NSString *error) {
        [app closeAllModals];
    } acceptPublicKeys:NO busyViewText:BC_STRING_LOADING_PROCESSING_KEY];
    
    [app.tabControllerManager.tabViewController presentViewController:privateKeyScanner animated:YES completion:nil];
}

- (void)setupFees
{
    self.feeType = FeeTypeRegular;

    [self arrangeViewsToFeeMode];
    
    [self reloadAfterMultiAddressResponse];
}

- (void)arrangeViewsToFeeMode
{
    [UIView animateWithDuration:ANIMATION_DURATION animations:^{
        
        if (IS_USING_SCREEN_SIZE_4S) {
            [lineBelowFromField changeYPosition:38];
            
            [toLabel changeYPosition:42];
            [toField changeYPosition:38];
            [addressBookButton changeYPosition:38];
            [lineBelowToField changeYPosition:66];
            
            [bottomContainerView changeYPosition:83];
            [btcLabel changeYPosition:-11];
            [btcAmountField changeYPosition:-15];
            [fiatLabel changeYPosition:-11];
            [fiatAmountField changeYPosition:-15];
            [lineBelowAmountFields changeYPosition:28];
            
            [feeTappableView changeYPosition:28];
            [feeField changeYPosition:38];
            [feeLabel changeYPosition:41];
            [self.feeTypeLabel changeYPosition:37];
            [self.feeDescriptionLabel changeYPosition:51];
            [self.feeAmountLabel changeYPosition:51 - self.feeAmountLabel.frame.size.height/2];
            [feeOptionsButton changeYPosition:37];
            [lineBelowFeeField changeYPosition:76];
            
            [fundsAvailableButton changeYPosition:6];
        }
        
        feeLabel.hidden = NO;
        feeOptionsButton.hidden = NO;
        lineBelowFeeField.hidden = NO;
        
        self.feeAmountLabel.hidden = NO;
        self.feeDescriptionLabel.hidden = NO;
        self.feeTypeLabel.hidden = NO;
    }];
    
    [self updateFeeLabels];
}

- (void)updateSendBalance:(NSNumber *)balance fees:(NSDictionary *)fees
{
    self.fees = fees;
    
    uint64_t newBalance = [balance longLongValue] <= 0 ? 0 : [balance longLongValue];
    
    availableAmount = newBalance;
    
    if (self.feeType != FeeTypeRegular) {
        [self updateSatoshiPerByteWithUpdateType:FeeUpdateTypeNoAction];
    }
    
    if (!self.transferAllPaymentBuilder || self.transferAllPaymentBuilder.userCancelledNext) {
        [self doCurrencyConversionAfterMultiAddress];
    }
}

- (void)updateTransferAllAmount:(NSNumber *)amount fee:(NSNumber *)fee addressesUsed:(NSArray *)addressesUsed
{
    if ([addressesUsed count] == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self showErrorBeforeSending:BC_STRING_NO_ADDRESSES_WITH_SPENDABLE_BALANCE_ABOVE_OR_EQUAL_TO_DUST];
            [app hideBusyView];
        });
        return;
    }
    
    if ([amount longLongValue] + [fee longLongValue] > [app.wallet getTotalBalanceForSpendableActiveLegacyAddresses]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * ANIMATION_DURATION * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [app standardNotifyAutoDismissingController:BC_STRING_SOME_FUNDS_CANNOT_BE_TRANSFERRED_AUTOMATICALLY title:BC_STRING_WARNING_TITLE];
            [app hideBusyView];
        });
    }
    
    self.fromAddress = @"";
    self.sendFromAddress = YES;
    self.sendToAddress = NO;
    self.toAccount = [app.wallet getDefaultAccountIndex];
    toField.text = [app.wallet getLabelForAccount:[app.wallet getDefaultAccountIndex]];
    
    self.feeFromTransactionProposal = [fee longLongValue];
    amountInSatoshi = [amount longLongValue];
        
    selectAddressTextField.text = [addressesUsed count] == 1 ? [NSString stringWithFormat:BC_STRING_ARGUMENT_ADDRESS, [addressesUsed count]] : [NSString stringWithFormat:BC_STRING_ARGUMENT_ADDRESSES, [addressesUsed count]];
    
    [self disablePaymentButtons];
    
    [self.transferAllPaymentBuilder setupFirstTransferWithAddressesUsed:addressesUsed];
}

- (void)showSummaryForTransferAll
{
    [app hideBusyView];
    
    [self showSummaryForTransferAllWithCustomFromLabel:selectAddressTextField.text];
    
    [self enablePaymentButtons];
    
    sendProgressCancelButton.hidden = [self.transferAllPaymentBuilder.transferAllAddressesToTransfer count] <= 1;
}

- (BOOL)transferAllMode
{
    return self.transferAllPaymentBuilder && !self.transferAllPaymentBuilder.userCancelledNext;
}

- (void)updateFeeLabels
{
    if (self.feeType == FeeTypeCustom) {
        feeField.hidden = NO;
        [feeTappableView changeXPosition:self.feeAmountLabel.frame.origin.x];
        
        self.feeAmountLabel.hidden = NO;
        self.feeAmountLabel.textColor = COLOR_LIGHT_GRAY;

        self.feeDescriptionLabel.hidden = YES;
        
        self.feeTypeLabel.hidden = YES;
    } else {
        feeField.hidden = YES;
        [feeTappableView changeXPosition:0];

        self.feeWarningLabel.hidden = YES;
        [lineBelowFeeField changeYPositionAnimated:[self defaultYPositionForWarningLabel] completion:nil];

        self.feeAmountLabel.hidden = NO;
        self.feeAmountLabel.textColor = COLOR_TEXT_DARK_GRAY;
        self.feeAmountLabel.text = nil;
        
        self.feeDescriptionLabel.hidden = NO;
        
        self.feeTypeLabel.hidden = NO;
        
        NSString *typeText;
        NSString *descriptionText;
        
        if (self.feeType == FeeTypeRegular) {
            typeText = BC_STRING_REGULAR;
            descriptionText = BC_STRING_GREATER_THAN_ONE_HOUR;
        } else if (self.feeType == FeeTypePriority) {
            typeText = BC_STRING_PRIORITY;
            descriptionText = BC_STRING_LESS_THAN_ONE_HOUR;
        }
        
        self.feeTypeLabel.text = typeText;
        self.feeDescriptionLabel.text = descriptionText;
    }
}

- (void)updateFeeAmountLabelText:(uint64_t)fee
{
    self.lastDisplayedFee = fee;
    
    if (self.feeType == FeeTypeCustom) {
        NSNumber *regularFee = [self.fees objectForKey:DICTIONARY_KEY_FEE_REGULAR];
        NSNumber *priorityFee = [self.fees objectForKey:DICTIONARY_KEY_FEE_PRIORITY];
        self.feeAmountLabel.text = [NSString stringWithFormat:@"%@: %@, %@: %@", BC_STRING_REGULAR, regularFee, BC_STRING_PRIORITY, priorityFee];
    } else {
        self.feeAmountLabel.text = [NSString stringWithFormat:@"%@ (%@)", [NSNumberFormatter formatMoney:fee localCurrency:NO], [NSNumberFormatter formatMoney:fee localCurrency:YES]];
    }
}

- (void)setupFeeWarningLabelFrameSmall
{
    CGFloat warningLabelOriginY = self.feeAmountLabel.frame.origin.y + self.feeAmountLabel.frame.size.height - 4;
    self.feeWarningLabel.frame = CGRectMake(feeField.frame.origin.x, warningLabelOriginY, feeOptionsButton.frame.origin.x - feeField.frame.origin.x, lineBelowFeeField.frame.origin.y - warningLabelOriginY);
}

- (void)setupFeeWarningLabelFrameLarge
{
    CGFloat warningLabelOriginY = self.feeDescriptionLabel.frame.origin.y + self.feeDescriptionLabel.frame.size.height - 4;
    self.feeWarningLabel.frame = CGRectMake(feeField.frame.origin.x, warningLabelOriginY, feeOptionsButton.frame.origin.x - feeField.frame.origin.x, lineBelowFeeField.frame.origin.y - warningLabelOriginY);
}

- (CGFloat)defaultYPositionForWarningLabel
{
    return IS_USING_SCREEN_SIZE_4S ? 76 : 112;
}

- (void)showRejectPaymentButtonWithRejectionType:(RejectionType)rejectionType
{
    [rejectPaymentButton removeTarget:nil action:nil forControlEvents:UIControlEventAllTouchEvents];
    
    NSString *buttonTitle;
    UIColor *titleColor;
    
    if (rejectionType == RejectionTypeDecline) {
        buttonTitle = BC_STRING_DECLINE;
        titleColor = [UIColor whiteColor];
        rejectPaymentButton.backgroundColor = COLOR_BLOCKCHAIN_RED;
        [rejectPaymentButton addTarget:self action:@selector(declinePaymentClicked) forControlEvents:UIControlEventTouchUpInside];
    } else if (rejectionType == RejectionTypeCancel) {
        buttonTitle = BC_STRING_CANCEL_PAYMENT;
        titleColor = COLOR_LIGHT_GRAY;
        rejectPaymentButton.backgroundColor = [UIColor clearColor];
        [rejectPaymentButton addTarget:self action:@selector(cancelPaymentClicked) forControlEvents:UIControlEventTouchUpInside];
    }
    
    [rejectPaymentButton setTitle:buttonTitle forState:UIControlStateNormal];
    [rejectPaymentButton setTitleColor:titleColor forState:UIControlStateNormal];

    rejectPaymentButton.alpha = 0.0;
    rejectPaymentButton.hidden = NO;

    [UIView animateWithDuration:ANIMATION_DURATION animations:^{
        [continuePaymentButton changeYPosition:[self continuePaymentButtonOriginY] - 8 - continuePaymentButton.frame.size.height];
       rejectPaymentButton.alpha = 1.0;
    }];
}

- (void)hideRejectPaymentButton
{
    rejectPaymentButton.alpha = 1.0;
    
    [UIView animateWithDuration:ANIMATION_DURATION animations:^{
        rejectPaymentButton.alpha = 0.0;
        rejectPaymentButton
        .hidden = YES;
        [continuePaymentButton changeYPosition:[self continuePaymentButtonOriginY]];
    }];
}

- (void)hideContactLabel
{
    contactLabel.hidden = YES;
}

- (void)disableToField
{
    CGFloat alpha = 0.0;

    toField.enabled = NO;
    toField.alpha = alpha;
    
    addressBookButton.enabled = NO;
    addressBookButton.alpha = alpha;
}

- (void)enableToField
{
    CGFloat alpha = 1.0;
    
    toField.enabled = YES;
    toField.alpha = alpha;
    
    addressBookButton.enabled = YES;
    addressBookButton.alpha = alpha;
}

- (void)disableAmountViews
{
    CGFloat alpha = 0.5;
    
    btcAmountField.enabled = NO;
    btcAmountField.alpha = alpha;
    
    fiatAmountField.enabled = NO;
    fiatAmountField.alpha = alpha;
    
    fundsAvailableButton.enabled = NO;
    fundsAvailableButton.alpha = alpha;
}

- (void)enableAmountViews
{
    CGFloat alpha = 1.0;

    btcAmountField.enabled = YES;
    btcAmountField.alpha = alpha;
    
    fiatAmountField.enabled = YES;
    fiatAmountField.alpha = alpha;
    
    fundsAvailableButton.enabled = YES;
    fundsAvailableButton.alpha = alpha;
}

- (CGFloat)continuePaymentButtonOriginY
{
    CGFloat spacing = 12;
    return self.view.frame.size.height - BUTTON_HEIGHT - spacing;
}

- (void)confirmRejectPayment:(RejectionType)rejectionType
{
    NSString *title = rejectionType == RejectionTypeDecline ? BC_STRING_DECLINE : BC_STRING_CANCEL_PAYMENT;
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:BC_STRING_REJECT_PAYMENT_MESSAGE preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_GO_BACK style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        if (rejectionType == RejectionTypeDecline) {
            [app.wallet sendDeclination:self.contactTransaction];
        } else {
            [app.wallet sendCancellation:self.contactTransaction];
        }
    }]];
    [app.window.rootViewController presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Textfield Delegates

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if (![app.wallet isInitialized]) {
        DLog(@"Tried to access Send textField when not initialized!");
        return NO;
    }
    
    if (textField == selectAddressTextField) {
        // If we only have one account and no legacy addresses -> can't change from address
        if (!([app.wallet hasAccount] && ![app.wallet hasLegacyAddresses]
              && [app.wallet getActiveAccountsCount] == 1)) {
            [self selectFromAddressClicked:textField];
        }
        return NO;  // Hide both keyboard and blinking cursor.
    }
    
    return YES;
}

- (void)textFieldDidBeginEditing:(UITextField *)textField
{
    if (self.tapGesture == nil) {
        self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideKeyboard)];
        
        [self.view addGestureRecognizer:self.tapGesture];
    }
    
    if (textField == btcAmountField) {
        displayingLocalSymbolSend = NO;
    }
    else if (textField == fiatAmountField) {
        displayingLocalSymbolSend = YES;
    }
    
    [self doCurrencyConversion];
    
    self.transactionType = TransactionTypeRegular;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (textField == btcAmountField || textField == fiatAmountField) {
        
        NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
        NSArray  *points = [newString componentsSeparatedByString:@"."];
        NSLocale *locale = [textField.textInputMode.primaryLanguage isEqualToString:LOCALE_IDENTIFIER_AR] ? [NSLocale localeWithLocaleIdentifier:textField.textInputMode.primaryLanguage] : [NSLocale currentLocale];
        NSArray  *commas = [newString componentsSeparatedByString:[locale objectForKey:NSLocaleDecimalSeparator]];
        
        // Only one comma or point in input field allowed
        if ([points count] > 2 || [commas count] > 2)
            return NO;
        
        // Only 1 leading zero
        if (points.count == 1 || commas.count == 1) {
            if (range.location == 1 && ![string isEqualToString:@"."] && ![string isEqualToString:@","] && ![string isEqualToString:@"٫"] && [textField.text isEqualToString:@"0"]) {
                return NO;
            }
        }
        
        // When entering amount in BTC, max 8 decimal places
        if (textField == btcAmountField || textField == feeField) {
            // Max number of decimal places depends on bitcoin unit
            NSUInteger maxlength = [@(SATOSHI) stringValue].length - [@(SATOSHI / app.latestResponse.symbol_btc.conversion) stringValue].length;
            
            if (points.count == 2) {
                NSString *decimalString = points[1];
                if (decimalString.length > maxlength) {
                    return NO;
                }
            }
            else if (commas.count == 2) {
                NSString *decimalString = commas[1];
                if (decimalString.length > maxlength) {
                    return NO;
                }
            }
        }
        
        // Fiat currencies have a max of 3 decimal places, most of them actually only 2. For now we will use 2.
        else if (textField == fiatAmountField) {
            if (points.count == 2) {
                NSString *decimalString = points[1];
                if (decimalString.length > 2) {
                    return NO;
                }
            }
            else if (commas.count == 2) {
                NSString *decimalString = commas[1];
                if (decimalString.length > 2) {
                    return NO;
                }
            }
        }
        
        if (textField == fiatAmountField) {
            // Convert input amount to internal value
            NSString *amountString = [newString stringByReplacingOccurrencesOfString:@"," withString:@"."];
            if (![amountString containsString:@"."]) {
                amountString = [newString stringByReplacingOccurrencesOfString:@"٫" withString:@"."];
            }
            amountInSatoshi = app.latestResponse.symbol_local.conversion * [amountString doubleValue];
        }
        else if (textField == btcAmountField) {
            amountInSatoshi = [app.wallet parseBitcoinValueFromString:newString];
        }
        
        if (amountInSatoshi > BTC_LIMIT_IN_SATOSHI) {
            return NO;
        } else {
            [self performSelector:@selector(doCurrencyConversion) withObject:nil afterDelay:0.1f];
            return YES;
        }
        
    } else if (textField == feeField) {
        
        NSString *newString = [textField.text stringByReplacingCharactersInRange:range withString:string];
        
        if ([newString containsString:@"."] ||
            [newString containsString:@","] ||
            [newString containsString:@"٫"]) return NO;
        
        if (newString.length == 0) {
            self.feeWarningLabel.hidden = YES;
            [lineBelowFeeField changeYPositionAnimated:[self defaultYPositionForWarningLabel] completion:nil];
        }

        [self performSelector:@selector(updateSatoshiPerByteAfterTextChange) withObject:nil afterDelay:0.1f];
        
        return YES;
    } else if (textField == toField) {
        self.sendToAddress = true;
        self.toAddress = [textField.text stringByReplacingCharactersInRange:range withString:string];
        if (self.toAddress && [app.wallet isBitcoinAddress:self.toAddress]) {
            [self selectToAddress:self.toAddress];
            self.addressSource = DestinationAddressSourcePaste;
            return NO;
        }
        
        DLog(@"toAddress: %@", self.toAddress);
    }
    
    return YES;
}

- (BOOL)textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    
    return YES;
}

- (void)updateFundsAvailable
{
    if (fiatAmountField.textColor == COLOR_WARNING_RED && btcAmountField.textColor == COLOR_WARNING_RED && [fiatAmountField.text isEqualToString:[NSNumberFormatter formatAmount:availableAmount localCurrency:YES]]) {
        [fundsAvailableButton setTitle:[NSString stringWithFormat:BC_STRING_USE_TOTAL_AVAILABLE_MINUS_FEE_ARGUMENT, [NSNumberFormatter formatMoney:availableAmount localCurrency:NO]] forState:UIControlStateNormal];
    } else {
        [fundsAvailableButton setTitle:[NSString stringWithFormat:BC_STRING_USE_TOTAL_AVAILABLE_MINUS_FEE_ARGUMENT,
                                        [NSNumberFormatter formatMoney:availableAmount localCurrency:displayingLocalSymbolSend]]
                              forState:UIControlStateNormal];
    }
}

- (void)selectFromAddress:(NSString *)address
{
    self.sendFromAddress = true;
    
    NSString *addressOrLabel;
    NSString *label = [app.wallet labelForLegacyAddress:address];
    if (label && ![label isEqualToString:@""]) {
        addressOrLabel = label;
    }
    else {
        addressOrLabel = address;
    }
    
    selectAddressTextField.text = addressOrLabel;
    self.fromAddress = address;
    DLog(@"fromAddress: %@", address);
    
    [app.wallet changePaymentFromAddress:address isAdvanced:self.feeType == FeeTypeCustom];
    
    [self doCurrencyConversion];
}

- (void)selectToAddress:(NSString *)address
{
    self.sendToAddress = true;
    self.toContact = nil;

    toField.text = [self labelForLegacyAddress:address];
    self.toAddress = address;
    DLog(@"toAddress: %@", address);
    
    [app.wallet changePaymentToAddress:address];
    
    self.contactTransaction = nil;
    
    [self doCurrencyConversion];
}

- (void)selectFromAccount:(int)account
{
    self.sendFromAddress = false;
    
    availableAmount = [app.wallet getBalanceForAccount:account];
    
    selectAddressTextField.text = [app.wallet getLabelForAccount:account];
    self.fromAccount = account;
    DLog(@"fromAccount: %@", [app.wallet getLabelForAccount:account]);
    
    [app.wallet changePaymentFromAccount:account isAdvanced:self.feeType == FeeTypeCustom];
    
    [self updateFundsAvailable];
    
    [self doCurrencyConversion];
}

- (void)selectToAccount:(int)account
{
    self.sendToAddress = false;
    self.toContact = nil;

    toField.text = [app.wallet getLabelForAccount:account];
    self.toAccount = account;
    self.toAddress = @"";
    DLog(@"toAccount: %@", [app.wallet getLabelForAccount:account]);
    
    [app.wallet changePaymentToAccount:account];
    
    self.contactTransaction = nil;
    
    [self doCurrencyConversion];
}

- (void)selectToContact:(Contact *)contact
{
    self.toContact = contact;
    
    toField.text = contact.name;
    DLog(@"toContact: %@", contact.name);

    [self doCurrencyConversion];
}

# pragma mark - AddressBook delegate

- (void)didSelectFromAddress:(NSString *)address
{
    [self selectFromAddress:address];
}

- (void)didSelectToAddress:(NSString *)address
{
    [self selectToAddress:address];
    
    self.addressSource = DestinationAddressSourceDropDown;
}

- (void)didSelectFromAccount:(int)account
{
    [self selectFromAccount:account];
}

- (void)didSelectToAccount:(int)account
{
    [self selectToAccount:account];
    
    self.addressSource = DestinationAddressSourceDropDown;
}

- (void)didSelectContact:(Contact *)contact
{
    if (!contact.mdid) {
        UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:BC_STRING_CONTACT_ARGUMENT_HAS_NOT_ACCEPTED_INVITATION_YET, contact.name] message:[NSString stringWithFormat:BC_STRING_CONTACT_ARGUMENT_MUST_ACCEPT_INVITATION, contact.name] preferredStyle:UIAlertControllerStyleAlert];
        [errorAlert addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:nil]];
        [app.tabControllerManager.tabViewController presentViewController:errorAlert animated:YES completion:nil];
    } else {
        [self selectToContact:contact];
    }
}

#pragma mark - Contacts

- (void)createSendRequest:(RequestType)requestType forContact:(Contact *)contact reason:(NSString *)reason
{
    id accountOrAddress;
    if (self.sendFromAddress) {
        accountOrAddress = self.fromAddress;
    } else {
        accountOrAddress = [NSNumber numberWithInt:self.fromAccount];
    }
    
    BCContactRequestView *contactRequestView = [[BCContactRequestView alloc] initWithContact:contact amount:amountInSatoshi willSend:YES accountOrAddress:accountOrAddress];
    contactRequestView.delegate = self;
    
    [app showModalWithContent:contactRequestView closeType:ModalCloseTypeBack headerText:BC_STRING_SEND_TO_CONTACT];
}

#pragma mark - Contact Request Delegate

- (void)createReceiveRequestForContact:(Contact *)contact withReason:(NSString *)reason amount:(uint64_t)amount lastSelectedField:(UITextField *)textField
{
    DLog(@"Send error: created receive request");
}

- (void)createSendRequestForContact:(Contact *)contact withReason:(NSString *)reason amount:(uint64_t)amount lastSelectedField:(UITextField *)textField accountOrAddress:(id)accountOrAddress
{
    DLog(@"Creating send request with reason: %@, amount: %lld", reason, amount);
    [textField resignFirstResponder];
    [app showBusyViewWithLoadingText:BC_STRING_LOADING_CREATING_REQUEST];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [app.wallet requestPaymentRequest:contact.identifier amount:amount requestId:nil note:reason initiatorSource:accountOrAddress];
    });
}

#pragma mark - Transaction Description Delegate

- (void)setupNoteForTransaction:(NSString *)note
{
    self.noteToSet = note;
}

#pragma mark - Fee Calculation

- (void)getTransactionFeeWithSuccess:(void (^)())success error:(void (^)())error
{
    self.getTransactionFeeSuccess = success;
    
    [app.wallet getTransactionFeeWithUpdateType:FeeUpdateTypeConfirm];
}

- (void)didCheckForOverSpending:(NSNumber *)amount fee:(NSNumber *)fee
{
    if ([amount longLongValue] <= 0) {
        [self handleZeroSpendableAmount];
        return;
    }
    
    self.feeFromTransactionProposal = [fee longLongValue];
    uint64_t maxAmount = [amount longLongValue];
    self.maxSendableAmount = maxAmount;
    
    __weak SendBitcoinViewController *weakSelf = self;
    
    [self getTransactionFeeWithSuccess:^{
        [weakSelf showSummary];
    } error:nil];
}

- (void)didGetMaxFee:(NSNumber *)fee amount:(NSNumber *)amount dust:(NSNumber *)dust willConfirm:(BOOL)willConfirm
{
    if ([amount longLongValue] <= 0) {
        [self handleZeroSpendableAmount];
        return;
    }
    
    self.feeFromTransactionProposal = [fee longLongValue];
    uint64_t maxAmount = [amount longLongValue];
    self.maxSendableAmount = maxAmount;
    self.dust = dust == nil ? 0 : [dust longLongValue];
    
    DLog(@"SendViewController: got max fee of %lld", [fee longLongValue]);
    amountInSatoshi = maxAmount;
    [self doCurrencyConversion];
    
    if (willConfirm) {
        [self showSummary];
    }
}

- (void)didUpdateTotalAvailable:(NSNumber *)sweepAmount finalFee:(NSNumber *)finalFee
{
    availableAmount = [sweepAmount longLongValue];
    uint64_t fee = [finalFee longLongValue];
    
    CGFloat warningLabelYPosition = [self defaultYPositionForWarningLabel];
    
    if (availableAmount <= 0 || availableAmount < fee) {
        [lineBelowFeeField changeYPositionAnimated:warningLabelYPosition + 30 completion:^(BOOL finished) {
            if (self.feeType == FeeTypeCustom) {
                [self setupFeeWarningLabelFrameSmall];
            } else {
                [self setupFeeWarningLabelFrameLarge];
            }
            self.feeWarningLabel.hidden = lineBelowFeeField.frame.origin.y == warningLabelYPosition;
        }];
        self.feeWarningLabel.text = BC_STRING_NOT_ENOUGH_FUNDS_TO_USE_FEE;
    } else {
        if ([self.feeWarningLabel.text isEqualToString:BC_STRING_NOT_ENOUGH_FUNDS_TO_USE_FEE]) {
            [lineBelowFeeField changeYPositionAnimated:warningLabelYPosition completion:nil];
            self.feeWarningLabel.hidden = YES;
        }
    }
    
    [self updateFeeAmountLabelText:fee];
    [self doCurrencyConversionAfterMultiAddress];
}

- (void)didGetFee:(NSNumber *)fee dust:(NSNumber *)dust txSize:(NSNumber *)txSize
{
    self.feeFromTransactionProposal = [fee longLongValue];
    self.recommendedForcedFee = [fee longLongValue];
    self.dust = dust == nil ? 0 : [dust longLongValue];
    self.txSize = [txSize longLongValue];
    
    if (self.getTransactionFeeSuccess) {
        self.getTransactionFeeSuccess();
    }
}

- (void)didChangeSatoshiPerByte:(NSNumber *)sweepAmount fee:(NSNumber *)fee dust:(NSNumber *)dust updateType:(FeeUpdateType)updateType
{
    availableAmount = [sweepAmount longLongValue];
    
    if (updateType != FeeUpdateTypeConfirm) {
        if (amountInSatoshi > availableAmount) {
            feeField.textColor = COLOR_WARNING_RED;
            [self disablePaymentButtons];
        } else {
            [self removeHighlightFromAmounts];
            feeField.textColor = COLOR_TEXT_DARK_GRAY;
            [self enablePaymentButtons];
        }
    }
    
    [self updateFundsAvailable];
    
    uint64_t feeValue = [fee longLongValue];

    self.feeFromTransactionProposal = feeValue;
    self.dust = dust == nil ? 0 : [dust longLongValue];
    [self updateFeeAmountLabelText:feeValue];
    
    if (updateType == FeeUpdateTypeConfirm) {
        [self showSummary];
    } else if (updateType == FeeUpdateTypeSweep) {
        [app.wallet sweepPaymentAdvanced];
    }
}

- (void)checkMaxFee
{
    [app.wallet checkIfOverspending];
}

- (void)updateSatoshiPerByteAfterTextChange
{
    [self updateSatoshiPerByteWithUpdateType:FeeUpdateTypeNoAction];
}

- (void)updateSatoshiPerByteWithUpdateType:(FeeUpdateType)feeUpdateType
{
    if (self.feeType == FeeTypeCustom) {
        uint64_t typedSatoshiPerByte = [feeField.text longLongValue];
        
        NSDictionary *limits = [self.fees objectForKey:DICTIONARY_KEY_FEE_LIMITS];
        
        if (typedSatoshiPerByte < [[limits objectForKey:DICTIONARY_KEY_FEE_LIMITS_MIN] longLongValue]) {
            DLog(@"Fee rate lower than recommended");
            
            CGFloat warningLabelYPosition = [self defaultYPositionForWarningLabel];
            
            if (feeField.text.length > 0) {
                if (IS_USING_SCREEN_SIZE_LARGER_THAN_5S) {
                    [lineBelowFeeField changeYPositionAnimated:warningLabelYPosition + 12 completion:^(BOOL finished) {
                        [self setupFeeWarningLabelFrameSmall];
                        self.feeWarningLabel.hidden = lineBelowFeeField.frame.origin.y == warningLabelYPosition;
                    }];
                } else {
                    [lineBelowFeeField changeYPositionAnimated:[self defaultYPositionForWarningLabel] completion:^(BOOL finished) {
                        [self setupFeeWarningLabelFrameSmall];
                        self.feeWarningLabel.hidden = NO;
                    }];
                }
                self.feeWarningLabel.text = BC_STRING_LOW_FEE_NOT_RECOMMENDED;
            }
        } else if (typedSatoshiPerByte > [[limits objectForKey:DICTIONARY_KEY_FEE_LIMITS_MAX] longLongValue]) {
            DLog(@"Fee rate higher than recommended");
            
            CGFloat warningLabelYPosition = [self defaultYPositionForWarningLabel];

            if (feeField.text.length > 0) {
                if (IS_USING_SCREEN_SIZE_LARGER_THAN_5S) {
                    [lineBelowFeeField changeYPositionAnimated:warningLabelYPosition + 12 completion:^(BOOL finished) {
                        [self setupFeeWarningLabelFrameSmall];
                        self.feeWarningLabel.hidden = lineBelowFeeField.frame.origin.y == warningLabelYPosition;
                    }];
                } else {
                    [lineBelowFeeField changeYPositionAnimated:[self defaultYPositionForWarningLabel] completion:^(BOOL finished) {
                        [self setupFeeWarningLabelFrameSmall];
                        self.feeWarningLabel.hidden = NO;
                    }];
                }
                self.feeWarningLabel.text = BC_STRING_HIGH_FEE_NOT_NECESSARY;
            }
        } else {
            [lineBelowFeeField changeYPositionAnimated:[self defaultYPositionForWarningLabel] completion:nil];
            self.feeWarningLabel.hidden = YES;
        }
        
        [app.wallet changeSatoshiPerByte:typedSatoshiPerByte updateType:feeUpdateType];
        
    } else if (self.feeType == FeeTypeRegular) {
        uint64_t regularRate = [[self.fees objectForKey:DICTIONARY_KEY_FEE_REGULAR] longLongValue];
        [app.wallet changeSatoshiPerByte:regularRate updateType:feeUpdateType];
    } else if (self.feeType == FeeTypePriority) {
        uint64_t priorityRate = [[self.fees objectForKey:DICTIONARY_KEY_FEE_PRIORITY] longLongValue];
        [app.wallet changeSatoshiPerByte:priorityRate updateType:feeUpdateType];
    }
}

- (void)selectFeeType:(FeeType)feeType
{
    self.feeType = feeType;
    
    [self updateFeeLabels];
    
    [self updateSatoshiPerByteWithUpdateType:FeeUpdateTypeNoAction];

    [app closeModalWithTransition:kCATransitionFromLeft];
}

#pragma mark - Fee Selection Delegate

- (void)didSelectFeeType:(FeeType)feeType
{
    if (feeType == FeeTypeCustom) {
        BOOL hasSeenWarning = [[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_HAS_SEEN_CUSTOM_FEE_WARNING];
        if (!hasSeenWarning) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:BC_STRING_WARNING_TITLE message:BC_STRING_CUSTOM_FEE_WARNING preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_CONTINUE style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                [self selectFeeType:feeType];
                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:USER_DEFAULTS_KEY_HAS_SEEN_CUSTOM_FEE_WARNING];
            }]];
            [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_CANCEL style:UIAlertActionStyleCancel handler:nil]];
            [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
        } else {
            [self selectFeeType:feeType];
        }
    } else {
        [self selectFeeType:feeType];
    }
}

- (FeeType)selectedFeeType
{
    return self.feeType;
}

#pragma mark - Actions

- (void)declinePaymentClicked
{
    [self confirmRejectPayment:RejectionTypeDecline];
}

- (void)cancelPaymentClicked
{
    [self confirmRejectPayment:RejectionTypeCancel];
}

- (void)setupTransferAll
{
    self.transferAllPaymentBuilder = [[TransferAllFundsBuilder alloc] initUsingSendScreen:YES];
    self.transferAllPaymentBuilder.delegate = self;
}

- (void)archiveTransferredAddresses
{
    [app showBusyViewWithLoadingText:[NSString stringWithFormat:BC_STRING_ARCHIVING_ADDRESSES]];
                                      
    [app.wallet archiveTransferredAddresses:self.transferAllPaymentBuilder.transferAllAddressesTransferred];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(finishedArchivingTransferredAddresses) name:NOTIFICATION_KEY_BACKUP_SUCCESS object:nil];
}

- (void)finishedArchivingTransferredAddresses
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NOTIFICATION_KEY_BACKUP_SUCCESS object:nil];
    [app closeAllModals];
}

- (IBAction)selectFromAddressClicked:(id)sender
{
    if (![app.wallet isInitialized]) {
        DLog(@"Tried to access select from screen when not initialized!");
        return;
    }
    
    BCAddressSelectionView *addressSelectionView = [[BCAddressSelectionView alloc] initWithWallet:app.wallet selectMode:SelectModeSendFrom];
    addressSelectionView.delegate = self;
    
    [app showModalWithContent:addressSelectionView closeType:ModalCloseTypeBack showHeader:YES headerText:BC_STRING_SEND_FROM onDismiss:nil onResume:nil];
}

- (IBAction)addressBookClicked:(id)sender
{
    if (![app.wallet isInitialized]) {
        DLog(@"Tried to access select to screen when not initialized!");
        return;
    }
    
    BCAddressSelectionView *addressSelectionView = [[BCAddressSelectionView alloc] initWithWallet:app.wallet selectMode:SelectModeSendTo];
    addressSelectionView.delegate = self;
    
    [app showModalWithContent:addressSelectionView closeType:ModalCloseTypeBack showHeader:YES headerText:BC_STRING_SEND_TO onDismiss:nil onResume:nil];
}

- (BOOL)startReadingQRCode
{
    AVCaptureDeviceInput *input = [app getCaptureDeviceInput:nil];
    
    if (!input) {
        return NO;
    }
    
    captureSession = [[AVCaptureSession alloc] init];
    [captureSession addInput:input];
    
    AVCaptureMetadataOutput *captureMetadataOutput = [[AVCaptureMetadataOutput alloc] init];
    [captureSession addOutput:captureMetadataOutput];
    
    dispatch_queue_t dispatchQueue;
    dispatchQueue = dispatch_queue_create("myQueue", NULL);
    [captureMetadataOutput setMetadataObjectsDelegate:self queue:dispatchQueue];
    [captureMetadataOutput setMetadataObjectTypes:[NSArray arrayWithObject:AVMetadataObjectTypeQRCode]];
    
    videoPreviewLayer = [[AVCaptureVideoPreviewLayer alloc] initWithSession:captureSession];
    [videoPreviewLayer setVideoGravity:AVLayerVideoGravityResizeAspectFill];
    
    CGRect frame = CGRectMake(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT);
    
    [videoPreviewLayer setFrame:frame];
    
    UIView *view = [[UIView alloc] initWithFrame:frame];
    [view.layer addSublayer:videoPreviewLayer];
    
    [app showModalWithContent:view closeType:ModalCloseTypeClose headerText:BC_STRING_SCAN_QR_CODE onDismiss:^{
        [captureSession stopRunning];
        captureSession = nil;
        [videoPreviewLayer removeFromSuperlayer];
    } onResume:nil];
    
    [captureSession startRunning];
    
    return YES;
}

- (void)stopReadingQRCode
{
    [app closeModalWithTransition:kCATransitionFade];
    
    // Go to the send scren if we are not already on it
    [app showSendCoins];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput didOutputMetadataObjects:(NSArray *)metadataObjects fromConnection:(AVCaptureConnection *)connection
{
    if (metadataObjects != nil && [metadataObjects count] > 0) {
        AVMetadataMachineReadableCodeObject *metadataObj = [metadataObjects firstObject];
        
        if ([[metadataObj type] isEqualToString:AVMetadataObjectTypeQRCode]) {
            [self performSelectorOnMainThread:@selector(stopReadingQRCode) withObject:nil waitUntilDone:NO];
            
            // do something useful with results
            dispatch_sync(dispatch_get_main_queue(), ^{
                NSDictionary *dict = [app parseURI:[metadataObj stringValue] prefix:PREFIX_BITCOIN_URI];
                
                NSString *address = [dict objectForKey:DICTIONARY_KEY_ADDRESS];
                
                if (address == nil || ![app.wallet isBitcoinAddress:address]) {
                    [app standardNotify:[NSString stringWithFormat:BC_STRING_INVALID_ADDRESS_ARGUMENT, address]];
                    return;
                }
                
                toField.text = [self labelForLegacyAddress:address];
                self.toAddress = address;
                self.sendToAddress = true;
                DLog(@"toAddress: %@", self.toAddress);
                [self selectToAddress:self.toAddress];
                
                self.addressSource = DestinationAddressSourceQR;
                
                NSString *amountStringFromDictionary = [dict objectForKey:DICTIONARY_KEY_AMOUNT];
                if ([NSNumberFormatter stringHasBitcoinValue:amountStringFromDictionary]) {
                    if (app.latestResponse.symbol_btc) {
                        NSDecimalNumber *amountDecimalNumber = [NSDecimalNumber decimalNumberWithString:amountStringFromDictionary];
                        amountInSatoshi = [[amountDecimalNumber decimalNumberByMultiplyingBy:(NSDecimalNumber *)[NSDecimalNumber numberWithDouble:SATOSHI]] longLongValue];
                    } else {
                        amountInSatoshi = 0.0;
                    }
                } else {
                    [self performSelector:@selector(doCurrencyConversion) withObject:nil afterDelay:0.1f];
                    return;
                }
                
                // If the amount is empty, open the amount field
                if (amountInSatoshi == 0) {
                    btcAmountField.text = nil;
                    fiatAmountField.text = nil;
                    [fiatAmountField becomeFirstResponder];
                }
                
                [self performSelector:@selector(doCurrencyConversion) withObject:nil afterDelay:0.1f];
                
            });
        }
    }
}

- (IBAction)QRCodebuttonClicked:(id)sender
{
    if (!captureSession) {
        [self startReadingQRCode];
    }
}

- (IBAction)closeKeyboardClicked:(id)sender
{
    [btcAmountField resignFirstResponder];
    [fiatAmountField resignFirstResponder];
    [toField resignFirstResponder];
    [feeField resignFirstResponder];
}

- (IBAction)feeOptionsClicked:(UIButton *)sender
{
    BCFeeSelectionView *feeSelectionView = [[BCFeeSelectionView alloc] initWithFrame:app.window.frame];
    feeSelectionView.delegate = self;
    [app showModalWithContent:feeSelectionView closeType:ModalCloseTypeBack headerText:BC_STRING_FEE];
}

- (IBAction)labelAddressClicked:(id)sender
{
    [app.wallet addToAddressBook:toField.text label:labelAddressTextField.text];
    
    [app closeModalWithTransition:kCATransitionFade];
    labelAddressTextField.text = @"";
    
    // Complete payment
    [self showSummary];
}

- (IBAction)useAllClicked:(id)sender
{
    [btcAmountField resignFirstResponder];
    [fiatAmountField resignFirstResponder];
    
    [app.wallet sweepPaymentRegular];
    
    self.transactionType = TransactionTypeSweep;
}

- (void)feeInformationButtonClicked
{
    NSString *title = BC_STRING_FEE_INFORMATION_TITLE;
    NSString *message = BC_STRING_FEE_INFORMATION_MESSAGE;
    
    if (self.feeType != FeeTypeCustom) {
        message = [message stringByAppendingString:BC_STRING_FEE_INFORMATION_MESSAGE_APPEND_REGULAR_SEND];
    }
    
    if (self.surgeIsOccurring || [[NSUserDefaults standardUserDefaults] boolForKey:USER_DEFAULTS_KEY_DEBUG_SIMULATE_SURGE]) {
        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", BC_STRING_SURGE_OCCURRING_MESSAGE]];
    }

    if (self.dust > 0) {
        message = [message stringByAppendingString:[NSString stringWithFormat:@"\n\n%@", BC_STRING_FEE_INFORMATION_DUST]];
    }

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:BC_STRING_OK style:UIAlertActionStyleCancel handler:nil]];
    [[NSNotificationCenter defaultCenter] addObserver:alert selector:@selector(autoDismiss) name:NOTIFICATION_KEY_RELOAD_TO_DISMISS_VIEWS object:nil];
    [app.tabControllerManager.tabViewController presentViewController:alert animated:YES completion:nil];
}

- (IBAction)sendPaymentClicked:(id)sender
{
    if (self.toContact) {
        
        uint64_t dust = [app.wallet dust];
        
        if (amountInSatoshi == 0) {
            [app standardNotify:BC_STRING_INVALID_SEND_VALUE];
        } else if (amountInSatoshi < dust) {
            [app standardNotify:[NSString stringWithFormat:BC_STRING_MUST_BE_ABOVE_OR_EQUAL_TO_DUST_THRESHOLD, dust]];
        } else {
            [self createSendRequest:RequestTypeSendReason forContact:self.toContact reason:nil];
        }
        return;
    }
    
    if ([self.toAddress length] == 0) {
        self.toAddress = toField.text;
        DLog(@"toAddress: %@", self.toAddress);
    }
    
    if ([self.toAddress length] == 0) {
        [self showErrorBeforeSending:BC_STRING_YOU_MUST_ENTER_DESTINATION_ADDRESS];
        return;
    }
    
    if (self.sendToAddress && ![app.wallet isBitcoinAddress:self.toAddress]) {
        [self showErrorBeforeSending:BC_STRING_INVALID_TO_BITCOIN_ADDRESS];
        return;
    }
    
    if (!self.sendFromAddress && !self.sendToAddress && self.fromAccount == self.toAccount) {
        [self showErrorBeforeSending:BC_STRING_FROM_TO_DIFFERENT];
        return;
    }
    
    if (self.sendFromAddress && self.sendToAddress && [self.fromAddress isEqualToString:self.toAddress]) {
        [self showErrorBeforeSending:BC_STRING_FROM_TO_ADDRESS_DIFFERENT];
        return;
    }
    
    uint64_t value = amountInSatoshi;
    // Convert input amount to internal value
    NSString *language = btcAmountField.textInputMode.primaryLanguage;
    NSLocale *locale = language ? [NSLocale localeWithLocaleIdentifier:language] : [NSLocale currentLocale];
    NSString *amountString = [btcAmountField.text stringByReplacingOccurrencesOfString:[locale objectForKey:NSLocaleDecimalSeparator] withString:@"."];
    
    NSString *europeanComma = @",";
    NSString *arabicComma= @"٫";
    
    if ([amountString containsString:europeanComma]) {
        amountString = [btcAmountField.text stringByReplacingOccurrencesOfString:europeanComma withString:@"."];
    } else if ([amountString containsString:arabicComma]) {
        amountString = [btcAmountField.text stringByReplacingOccurrencesOfString:arabicComma withString:@"."];
    }
    if (value <= 0 || [amountString doubleValue] <= 0) {
        [self showErrorBeforeSending:BC_STRING_INVALID_SEND_VALUE];
        return;
    }
    
    [self hideKeyboard];
    
    [self disablePaymentButtons];
    
    self.transactionType = TransactionTypeRegular;
    
    if (self.feeType == FeeTypeCustom) {
        [self updateSatoshiPerByteWithUpdateType:FeeUpdateTypeConfirm];
    } else {
        [self checkMaxFee];
    }
    
    [app.wallet getSurgeStatus];
    
    //    if ([[app.wallet.addressBook objectForKey:self.toAddress] length] == 0 && ![app.wallet.allLegacyAddresses containsObject:self.toAddress]) {
    //        UIAlertView *alert = [[UIAlertView alloc] initWithTitle:BC_STRING_ADD_TO_ADDRESS_BOOK
    //                                                        message:[NSString stringWithFormat:BC_STRING_ASK_TO_ADD_TO_ADDRESS_BOOK, self.toAddress]
    //                                                       delegate:nil
    //                                              cancelButtonTitle:BC_STRING_NO
    //                                              otherButtonTitles:BC_STRING_YES, nil];
    //
    //        alert.tapBlock = ^(UIAlertView *alertView, NSInteger buttonIndex) {
    //            // do nothing & proceed
    //            if (buttonIndex == 0) {
    //                [self confirmPayment];
    //            }
    //            // let user save address in addressbook
    //            else if (buttonIndex == 1) {
    //                labelAddressLabel.text = toField.text;
    //
    //                [app showModal:labelAddressView isClosable:TRUE];
    //
    //                [labelAddressTextField becomeFirstResponder];
    //            }
    //        };
    //        
    //        [alert show];
    //    } else {
    //        [self confirmPayment];
    //    }
}

@end
