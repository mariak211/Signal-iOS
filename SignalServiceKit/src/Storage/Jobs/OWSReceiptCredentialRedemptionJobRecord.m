//
//  Copyright (c) 2020 Open Whisper Systems. All rights reserved.
//

#import "OWSReceiptCredentialRedemptionJobRecord.h"

@implementation OWSReceiptCredentialRedemptionJobRecord

- (instancetype)initWithReceiptCredentialRequestContext:(NSData *)receiptCredentailRequestContext
                               receiptCredentailRequest:(NSData *)receiptCredentialRequest
                                           subscriberID:(NSData *)subscriberID
                                targetSubscriptionLevel:(NSUInteger)targetSubscriptionLevel
                                 priorSubscriptionLevel:(NSUInteger)priorSubscriptionLevel
                                                isBoost:(BOOL)isBoost
                                   boostPaymentIntentID:(NSString *)boostPaymentIntentID
                                                  label:(NSString *)label
{
    self = [super initWithLabel:label];
    if (self) {
        _receiptCredentailRequestContext = receiptCredentailRequestContext;
        _receiptCredentailRequest = receiptCredentialRequest;
        _subscriberID = subscriberID;
        _targetSubscriptionLevel = targetSubscriptionLevel;
        _priorSubscriptionLevel = priorSubscriptionLevel;
        _isBoost = isBoost;
        _boostPaymentIntentID = _boostPaymentIntentID;
    }
    return self;
}

- (nullable instancetype)initWithCoder:(NSCoder *)coder
{
    return [super initWithCoder:coder];
}

// --- CODE GENERATION MARKER

// This snippet is generated by /Scripts/sds_codegen/sds_generate.py. Do not manually edit it, instead run
// `sds_codegen.sh`.

// clang-format off

- (instancetype)initWithGrdbId:(int64_t)grdbId
                      uniqueId:(NSString *)uniqueId
      exclusiveProcessIdentifier:(nullable NSString *)exclusiveProcessIdentifier
                    failureCount:(NSUInteger)failureCount
                           label:(NSString *)label
                          sortId:(unsigned long long)sortId
                          status:(SSKJobRecordStatus)status
            boostPaymentIntentID:(NSString *)boostPaymentIntentID
                         isBoost:(BOOL)isBoost
          priorSubscriptionLevel:(NSUInteger)priorSubscriptionLevel
        receiptCredentailRequest:(NSData *)receiptCredentailRequest
 receiptCredentailRequestContext:(NSData *)receiptCredentailRequestContext
                    subscriberID:(NSData *)subscriberID
         targetSubscriptionLevel:(NSUInteger)targetSubscriptionLevel
{
    self = [super initWithGrdbId:grdbId
                        uniqueId:uniqueId
        exclusiveProcessIdentifier:exclusiveProcessIdentifier
                      failureCount:failureCount
                             label:label
                            sortId:sortId
                            status:status];

    if (!self) {
        return self;
    }

    _boostPaymentIntentID = boostPaymentIntentID;
    _isBoost = isBoost;
    _priorSubscriptionLevel = priorSubscriptionLevel;
    _receiptCredentailRequest = receiptCredentailRequest;
    _receiptCredentailRequestContext = receiptCredentailRequestContext;
    _subscriberID = subscriberID;
    _targetSubscriptionLevel = targetSubscriptionLevel;

    return self;
}

// clang-format on

// --- CODE GENERATION MARKER

@end
