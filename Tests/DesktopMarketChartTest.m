#import <AppKit/AppKit.h>
#import "DesktopMarketChart.h"
#import "DesktopMarketService.h"

static DesktopCandle *MakeCandle(NSInteger minute) {
    DesktopCandle *candle = [DesktopCandle new];
    candle.time = [NSDate dateWithTimeIntervalSince1970:1795060800 + minute * 60];
    candle.open = 100;
    candle.high = 102;
    candle.low = 99;
    candle.close = 101;
    return candle;
}

static NSEvent *MouseEvent(NSEventType type, CGFloat x) {
    return [NSEvent mouseEventWithType:type location:NSMakePoint(x, 120) modifierFlags:0 timestamp:0
                         windowNumber:0 context:nil eventNumber:0 clickCount:1 pressure:1];
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        DesktopMarketChart *chart = [[DesktopMarketChart alloc] initWithFrame:NSMakeRect(0, 0, 620, 270)];
        NSMutableArray<DesktopCandle *> *candles = [NSMutableArray array];
        for (NSInteger minute = 0; minute < 480; minute++) {
            [candles addObject:MakeCandle(minute)];
        }
        chart.candles = candles;
        NSCAssert(NSEqualRanges(chart.visibleCandleRange, NSMakeRange(360, 120)), @"Initial view follows latest");

        [chart mouseDown:MouseEvent(NSEventTypeLeftMouseDown, 140)];
        [chart mouseDragged:MouseEvent(NSEventTypeLeftMouseDragged, 402)];
        [chart mouseUp:MouseEvent(NSEventTypeLeftMouseUp, 402)];
        NSCAssert(NSEqualRanges(chart.visibleCandleRange, NSMakeRange(300, 120)), @"Dragging right shows older candles");

        NSDate *rightEdge = candles[NSMaxRange(chart.visibleCandleRange) - 1].time;
        [candles insertObject:MakeCandle(-1) atIndex:0];
        [candles addObject:MakeCandle(480)];
        chart.candles = candles;
        NSCAssert([rightEdge isEqual:candles[NSMaxRange(chart.visibleCandleRange) - 1].time],
                  @"Older history and new quotes preserve the viewed time range");

        [chart showLatest];
        NSCAssert(NSMaxRange(chart.visibleCandleRange) == candles.count, @"Latest resumes following the feed");
        NSArray *history = DesktopMergeMinuteCandles(@[], candles, nil);
        NSCAssert(history.count == candles.count, @"Full detail history is not limited to the rolling quote cache");
        puts("Desktop chart: dragging, stable history position and latest view passed");
        return 0;
    }
}
