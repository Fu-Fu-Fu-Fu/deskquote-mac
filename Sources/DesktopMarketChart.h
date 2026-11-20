#import <AppKit/AppKit.h>

@class DesktopCandle, DesktopQuote;

@interface DesktopMarketChart : NSView
@property (nonatomic, copy) NSArray<DesktopCandle *> *candles;
@property (nonatomic, copy) NSArray<DesktopCandle *> *dailyReferences;
@property (nonatomic, strong, nullable) DesktopQuote *quote;
@property (nonatomic) BOOL miniature;
@property (nonatomic) BOOL daily;
@property (nonatomic) NSInteger precision;
@property (nonatomic, readonly) NSRange visibleCandleRange;
- (void)resetViewport;
- (void)showLatest;
@end

NSColor *DesktopColor(unsigned int rgb);
