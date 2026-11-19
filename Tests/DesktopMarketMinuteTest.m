#import <Foundation/Foundation.h>
#import "DesktopMarketService.h"

static DesktopCandle *Bar(NSDate *minute, double open, double high, double low, double close) {
    DesktopCandle *bar = [DesktopCandle new];
    bar.time = minute;
    bar.open = open;
    bar.high = high;
    bar.low = low;
    bar.close = close;
    return bar;
}

int main(void) {
    @autoreleasepool {
        NSDate *first = [NSDate dateWithTimeIntervalSince1970:1795060800];
        NSDate *second = [first dateByAddingTimeInterval:60];
        DesktopQuote *quote = [DesktopQuote new];
        quote.minute = first;
        quote.price = 107;
        NSArray<DesktopCandle *> *history = @[Bar(first, 100, 105, 98, 103)];
        NSArray<DesktopCandle *> *merged = DesktopMergeMinuteCandles(@[], history, quote);
        NSCAssert(merged.count == 1 && merged.lastObject.open == 100 &&
                  merged.lastObject.high == 107 && merged.lastObject.close == 107, @"Opening minute");

        quote.price = 96;
        merged = DesktopMergeMinuteCandles(merged, history, quote);
        NSCAssert(merged.count == 1 && merged.lastObject.high == 107 &&
                  merged.lastObject.low == 96 && merged.lastObject.close == 96, @"In-progress extremes");

        quote.minute = second;
        quote.price = 104;
        merged = DesktopMergeMinuteCandles(merged, @[], quote);
        NSCAssert(merged.count == 2 && merged.firstObject.close == 96 &&
                  merged.lastObject.open == 104 && merged.lastObject.close == 104, @"Minute boundary");

        quote.minute = first;
        NSArray<DesktopCandle *> *updated = @[Bar(first, 100, 108, 95, 101), Bar(second, 102, 110, 100, 108)];
        merged = DesktopMergeMinuteCandles(merged, updated, quote);
        NSCAssert(merged.count == 2 && merged.firstObject.close == 101 &&
                  merged.lastObject.close == 108, @"Newer history wins over an older quote");

        NSDictionary<NSString *, NSString *> *aliases = @{
            @"纳斯达克指数期货CFD": @"NQ-CFD", @"NQ": @"NQ=F", @"浙商黄金": @"CZB-GOLD",
            @"上证指数": @"SH000001", @"000001": @"000001.SZ", @"科创50": @"SH000688"
        };
        for (NSString *name in aliases) {
            NSCAssert([[DesktopMarketService normalizedSymbol:name] isEqualToString:aliases[name]], @"Symbol %@", name);
        }
        NSCAssert(DesktopMarketService.defaultSymbols.count == 7, @"Default markets");
        puts("Desktop market: minute updates, corrections, and instrument identities passed");
        return 0;
    }
}
