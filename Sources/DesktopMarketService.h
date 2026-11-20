#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DesktopCandle : NSObject
@property (nonatomic, strong) NSDate *time;
@property (nonatomic) double open;
@property (nonatomic) double high;
@property (nonatomic) double low;
@property (nonatomic) double close;
@end

@interface DesktopQuote : NSObject
@property (nonatomic, copy) NSString *symbol;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *currency;
@property (nonatomic, copy) NSString *source;
@property (nonatomic, strong) NSDate *time;
@property (nonatomic, strong, nullable) NSDate *minute;
@property (nonatomic) double price;
@property (nonatomic) double previousClose;
@property (nonatomic) double dayHigh;
@property (nonatomic) double dayLow;
@property (nonatomic) NSInteger precision;
@property (nonatomic) NSInteger delayMinutes;
@property (nonatomic, readonly) double change;
@property (nonatomic, readonly) double changePercent;
@end

NSArray<DesktopCandle *> *DesktopMergeMinuteCandles(NSArray<DesktopCandle *> *previous,
                                                    NSArray<DesktopCandle *> *history,
                                                    DesktopQuote *_Nullable quote);

@interface DesktopMarketService : NSObject
+ (NSArray<NSString *> *)defaultSymbols;
+ (NSArray<NSString *> *)addedMarketSymbols;
+ (BOOL)hasSeparateMinuteHistory:(NSString *)symbol;
+ (nullable NSString *)normalizedSymbol:(NSString *)input;
+ (NSString *)displayNameForSymbol:(NSString *)symbol;
+ (NSURL *)webURLForSymbol:(NSString *)symbol;
- (void)fetchQuote:(NSString *)symbol
        completion:(void (^)(DesktopQuote * _Nullable quote, NSArray<DesktopCandle *> *candles))completion;
- (void)fetchCandles:(NSString *)symbol
              daily:(BOOL)daily
           extended:(BOOL)extended
         completion:(void (^)(NSArray<DesktopCandle *> *candles))completion;
@end

NS_ASSUME_NONNULL_END
