#import <AppKit/AppKit.h>

@class DesktopCandle;

@interface DesktopMarketChart : NSView
@property (nonatomic, copy) NSArray<DesktopCandle *> *candles;
@property (nonatomic) BOOL miniature;
@property (nonatomic) BOOL daily;
@property (nonatomic) NSInteger precision;
@property (nonatomic, readonly) NSRange visibleCandleRange;
- (void)resetViewport;
- (void)showLatest;
@end

NSColor *DesktopColor(unsigned int rgb);
