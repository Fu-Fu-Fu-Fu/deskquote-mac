#import <Foundation/Foundation.h>
#import "DesktopMarketService.h"
#import <math.h>

static DesktopCandle *Bar(NSDate *minute, double open, double high, double low, double close) {
    DesktopCandle *bar = [DesktopCandle new];
    bar.time = minute;
    bar.open = open;
    bar.high = high;
    bar.low = low;
    bar.close = close;
    return bar;
}

static void TestPreviousTradingDayPrice(void) {
    NSDate *time = [NSDate dateWithTimeIntervalSince1970:1795060800];
    DesktopCandle *friday = Bar(time, 95, 105, 95, 100);
    friday.tradingDay = @"2026-11-13";
    DesktopCandle *monday = Bar(time, 102, 110, 99, 106);
    monday.tradingDay = @"2026-11-16";
    DesktopCandle *tuesday = Bar(time, 106, 114, 104, 112);
    tuesday.tradingDay = @"2026-11-17";
    NSArray *daily = @[friday, monday, tuesday];

    DesktopQuote *quote = [DesktopQuote new];
    quote.tradingDay = tuesday.tradingDay;
    quote.previousClose = 107;
    quote.previousCloseIsSettlement = YES;
    BOOL settlement = NO;
    DesktopCandle *minute = Bar(time, 102, 108, 99, 104);
    minute.tradingDay = monday.tradingDay;
    NSCAssert(DesktopPreviousTradingDayPrice(minute, daily, quote, &settlement) == 100 && !settlement,
              @"Monday uses Friday's close, independent of the current quote");
    friday.settlement = 101;
    NSCAssert(DesktopPreviousTradingDayPrice(minute, daily, quote, &settlement) == 101 && settlement,
              @"Historical settlement when supplied");
    monday.previousSessionClose = 99;
    NSCAssert(DesktopPreviousTradingDayPrice(minute, daily, quote, &settlement) == 99 && !settlement,
              @"Provider's historical session reference takes precedence");
    minute.tradingDay = tuesday.tradingDay;
    NSCAssert(DesktopPreviousTradingDayPrice(minute, @[], quote, &settlement) == 107 && settlement,
              @"Live prior settlement is available before history loads");
    minute.tradingDay = @"2026-11-14";
    NSCAssert(isnan(DesktopPreviousTradingDayPrice(minute, daily, quote, &settlement)) && !settlement,
              @"An unknown session has no guessed reference");

    quote.minute = time;
    quote.price = 112;
    NSArray<DesktopCandle *> *merged = DesktopMergeMinuteCandles(@[], @[], quote);
    NSCAssert([merged.lastObject.tradingDay isEqualToString:tuesday.tradingDay], @"Live candle keeps its session date");
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
        TestPreviousTradingDayPrice();
        puts("Desktop market: minute updates, instrument identities, and prior trading-day references passed");
        return 0;
    }
}
