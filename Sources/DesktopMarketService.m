#import "DesktopMarketService.h"
#import <CoreFoundation/CoreFoundation.h>
#import <math.h>

@implementation DesktopCandle
@end

@implementation DesktopQuote
- (double)change {
    return self.previousClose > 0 ? self.price - self.previousClose : NAN;
}
- (double)changePercent {
    return self.change / self.previousClose * 100;
}
@end

static NSString * const GoldSymbol = @"XAUUSD";
static NSString * const IndexSymbol = @"^NDX";
static NSString * const FuturesSymbol = @"NQ=F";
static NSString * const CFDSymbol = @"NQ-CFD";
static NSString * const BankGoldSymbol = @"CZB-GOLD";
static NSString * const ShanghaiSymbol = @"SH000001";
static NSString * const Star50Symbol = @"SH000688";
static NSString * const SinaReferer = @"https://finance.sina.com.cn/";
static NSString * const JDBankGoldSKU = @"1961543816";

static NSDictionary<NSString *, NSString *> *SinaSymbols(void) {
    return @{GoldSymbol: @"hf_XAU", CFDSymbol: @"hf_NQ", ShanghaiSymbol: @"sh000001", Star50Symbol: @"sh000688"};
}

static BOOL IsShanghaiIndex(NSString *symbol) {
    return [symbol isEqualToString:ShanghaiSymbol] || [symbol isEqualToString:Star50Symbol];
}

static double Number(id value) {
    if ([value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) != CFBooleanGetTypeID()) {
        return [value doubleValue];
    }
    if ([value isKindOfClass:NSString.class]) {
        NSScanner *scanner = [NSScanner scannerWithString:value];
        scanner.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
        double result;
        if ([scanner scanDouble:&result] && scanner.isAtEnd) {
            return result;
        }
    }
    return NAN;
}

static BOOL IsPrice(double value) {
    return isfinite(value) && value > 0;
}

static DesktopCandle *Candle(NSDate *time, id open, id high, id low, id close) {
    double o = Number(open), h = Number(high), l = Number(low), c = Number(close);
    if (!time || !IsPrice(o) || !IsPrice(h) || !IsPrice(l) || !IsPrice(c) ||
        h < MAX(o, c) || l > MIN(o, c)) {
        return nil;
    }
    DesktopCandle *bar = [DesktopCandle new];
    bar.time = time;
    bar.open = o;
    bar.high = h;
    bar.low = l;
    bar.close = c;
    return bar;
}

static NSDate *MinuteStart(NSDate *time) {
    return [NSDate dateWithTimeIntervalSince1970:floor(time.timeIntervalSince1970 / 60) * 60];
}

NSArray<DesktopCandle *> *DesktopMergeMinuteCandles(NSArray<DesktopCandle *> *previous,
                                                    NSArray<DesktopCandle *> *history,
                                                    DesktopQuote *quote) {
    NSMutableDictionary<NSDate *, DesktopCandle *> *byTime = [NSMutableDictionary dictionary];
    for (DesktopCandle *candle in previous) {
        byTime[candle.time] = candle;
    }
    // A slower quote response must not overwrite a newer minute from the history feed.
    NSDate *activeMinute = quote.minute;
    if (activeMinute && history.lastObject &&
        [history.lastObject.time compare:activeMinute] == NSOrderedDescending) {
        activeMinute = nil;
    }
    for (DesktopCandle *candle in history) {
        if ([candle.time isEqual:activeMinute] && byTime[candle.time]) {
            DesktopCandle *prior = byTime[candle.time];
            byTime[candle.time] = Candle(candle.time, @(candle.open), @(fmax(candle.high, prior.high)),
                                         @(fmin(candle.low, prior.low)), @(candle.close));
        } else {
            byTime[candle.time] = candle;
        }
    }
    if (activeMinute) {
        DesktopCandle *bar = byTime[activeMinute];
        byTime[activeMinute] = Candle(activeMinute, @(bar ? bar.open : quote.price),
                                     @(bar ? fmax(bar.high, quote.price) : quote.price),
                                     @(bar ? fmin(bar.low, quote.price) : quote.price), @(quote.price));
    }
    NSArray<NSDate *> *times = [byTime.allKeys sortedArrayUsingSelector:@selector(compare:)];
    NSUInteger first = times.count > 300 ? times.count - 300 : 0;
    NSMutableArray<DesktopCandle *> *candles = [NSMutableArray arrayWithCapacity:times.count - first];
    for (NSUInteger i = first; i < times.count; i++) {
        [candles addObject:byTime[times[i]]];
    }
    return candles;
}

static NSDateFormatter *ShanghaiFormatter(NSString *format) {
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    formatter.timeZone = [NSTimeZone timeZoneWithName:@"Asia/Shanghai"];
    formatter.dateFormat = format;
    return formatter;
}

static id JSON(NSData *data) {
    return data.length ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
}

static id At(NSArray *values, NSUInteger index) {
    return [values isKindOfClass:NSArray.class] && index < values.count ? values[index] : nil;
}

static NSDictionary *Dictionary(id value) {
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

static NSString *String(id value) {
    return [value isKindOfClass:NSString.class] ? value : nil;
}

static NSString *PathSymbol(NSString *symbol) {
    return [symbol stringByAddingPercentEncodingWithAllowedCharacters:NSCharacterSet.alphanumericCharacterSet];
}

@implementation DesktopMarketService {
    NSURLSession *_session;
}

+ (NSArray<NSString *> *)defaultSymbols {
    return [@[IndexSymbol, FuturesSymbol, GoldSymbol] arrayByAddingObjectsFromArray:[self addedMarketSymbols]];
}

+ (NSArray<NSString *> *)addedMarketSymbols {
    return @[CFDSymbol, BankGoldSymbol, ShanghaiSymbol, Star50Symbol];
}

+ (BOOL)hasSeparateMinuteHistory:(NSString *)symbol {
    return SinaSymbols()[symbol] != nil || [symbol isEqualToString:BankGoldSymbol];
}

+ (NSString *)normalizedSymbol:(NSString *)input {
    NSString *value = [input stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].uppercaseString;
    if (!value.length) {
        return nil;
    }
    NSDictionary *aliases = @{
        @"NDX": IndexSymbol, @"NASDAQ:NDX": IndexSymbol, @"纳斯达克100": IndexSymbol, @"纳斯达克 100": IndexSymbol, @"纳指100": IndexSymbol,
        @"NQ": FuturesSymbol, @"NQ1!": FuturesSymbol, @"CME_MINI:NQ1!": FuturesSymbol, @"纳指期货": FuturesSymbol, @"纳斯达克期货": FuturesSymbol,
        @"XAU": GoldSymbol, @"XAU/USD": GoldSymbol, @"伦敦金": GoldSymbol,
        @"纳斯达克指数期货CFD": CFDSymbol, @"纳指期货CFD": CFDSymbol, @"HF_NQ": CFDSymbol,
        @"浙商黄金": BankGoldSymbol, @"浙商积存金": BankGoldSymbol, @"浙商银行积存金": BankGoldSymbol, @"JCJ": BankGoldSymbol,
        @"上证指数": ShanghaiSymbol, @"000001.SS": ShanghaiSymbol, @"000001.SH": ShanghaiSymbol,
        @"科创50": Star50Symbol, @"科创50指数": Star50Symbol, @"000688": Star50Symbol,
        @"000688.SS": Star50Symbol, @"000688.SH": Star50Symbol
    };
    value = aliases[value] ?: value;
    if ([value rangeOfString:@"^[0-9]{6}$" options:NSRegularExpressionSearch].location != NSNotFound) {
        if ([value hasPrefix:@"5"] || [value hasPrefix:@"6"]) {
            value = [value stringByAppendingString:@".SS"];
        } else if ([value hasPrefix:@"0"] || [value hasPrefix:@"1"] || [value hasPrefix:@"3"]) {
            value = [value stringByAppendingString:@".SZ"];
        }
    }
    return [value rangeOfString:@"^\\^?[A-Z0-9][A-Z0-9.=\\-]{0,23}$" options:NSRegularExpressionSearch].location != NSNotFound ? value : nil;
}

+ (NSString *)displayNameForSymbol:(NSString *)symbol {
    return @{IndexSymbol: @"纳斯达克 100", FuturesSymbol: @"纳指 E-mini 期货", GoldSymbol: @"伦敦金现货",
             CFDSymbol: @"纳指期货 CFD", BankGoldSymbol: @"浙商银行积存金",
             ShanghaiSymbol: @"上证指数", Star50Symbol: @"科创 50 指数"}[symbol] ?: symbol;
}

+ (NSURL *)webURLForSymbol:(NSString *)symbol {
    NSDictionary<NSString *, NSString *> *pages = @{
        GoldSymbol: @"https://finance.sina.com.cn/futures/quotes/XAU.shtml",
        CFDSymbol: @"https://finance.sina.com.cn/futures/quotes/NQ.shtml",
        BankGoldSymbol: @"https://m.jdjygold.com/finance-gold/gold-standard/home/?productSku=1961543816",
        ShanghaiSymbol: @"https://finance.sina.com.cn/realstock/company/sh000001/nc.shtml",
        Star50Symbol: @"https://finance.sina.com.cn/realstock/company/sh000688/nc.shtml"
    };
    if (pages[symbol]) {
        return [NSURL URLWithString:pages[symbol]];
    }
    return [NSURL URLWithString:[NSString stringWithFormat:@"https://finance.yahoo.com/quote/%@/", PathSymbol(symbol)]];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        NSURLSessionConfiguration *config = NSURLSessionConfiguration.ephemeralSessionConfiguration;
        config.timeoutIntervalForRequest = 7;
        config.timeoutIntervalForResource = 11;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        _session = [NSURLSession sessionWithConfiguration:config];
    }
    return self;
}

- (void)dealloc {
    [_session invalidateAndCancel];
}

- (void)get:(NSString *)url referer:(NSString *)referer completion:(void (^)(NSData *))completion {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:url]];
    [request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    if (referer) {
        [request setValue:referer forHTTPHeaderField:@"Referer"];
    }
    [self send:request completion:completion];
}

- (void)send:(NSURLRequest *)request completion:(void (^)(NSData *))completion {
    [[_session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        completion(!error && status >= 200 && status < 300 ? data : nil);
    }] resume];
}

- (void)yahooResponse:(NSString *)symbol daily:(BOOL)daily completion:(void (^)(NSDictionary *))completion {
    NSString *path = [NSString stringWithFormat:@"/v8/finance/chart/%@?range=%@&interval=%@&includePrePost=false",
                      PathSymbol(symbol), daily ? @"6mo" : @"1d", daily ? @"1d" : @"1m"];
    [self get:[@"https://query1.finance.yahoo.com" stringByAppendingString:path] referer:nil completion:^(NSData *data) {
        NSDictionary *root = Dictionary(Dictionary(JSON(data))[@"chart"]);
        NSDictionary *result = Dictionary(At(root[@"result"], 0));
        if (result || data.length > 0) {
            completion(result);
            return;
        }
        [self get:[@"https://query2.finance.yahoo.com" stringByAppendingString:path] referer:nil completion:^(NSData *fallback) {
            NSDictionary *backup = Dictionary(Dictionary(JSON(fallback))[@"chart"]);
            completion(Dictionary(At(backup[@"result"], 0)));
        }];
    }];
}

static double YahooRegularSessionEnd(NSDictionary *meta) {
    if ([String(meta[@"instrumentType"]) isEqualToString:@"FUTURE"]) {
        return NAN;
    }
    NSArray *sessions = At(meta[@"tradingPeriods"], 0);
    return Number(Dictionary(At(sessions, 0))[@"end"]);
}

- (NSArray<DesktopCandle *> *)yahooCandles:(NSDictionary *)result daily:(BOOL)daily {
    NSArray *times = result[@"timestamp"];
    if (![times isKindOfClass:NSArray.class]) {
        return @[];
    }
    NSDictionary *quote = Dictionary(At(Dictionary(result[@"indicators"])[@"quote"], 0));
    double sessionEnd = YahooRegularSessionEnd(Dictionary(result[@"meta"]));
    NSMutableArray<DesktopCandle *> *candles = [NSMutableArray array];
    for (NSUInteger i = 0; i < times.count; i++) {
        double timestamp = Number(times[i]);
        // Yahoo may append a quote snapshot with a timestamp between two one-minute bars.
        if (isfinite(timestamp) && timestamp > 0 &&
            (daily || (fmod(timestamp, 60) == 0 && (!isfinite(sessionEnd) || timestamp < sessionEnd)))) {
            DesktopCandle *candle = Candle([NSDate dateWithTimeIntervalSince1970:timestamp],
                                            At(quote[@"open"], i), At(quote[@"high"], i),
                                            At(quote[@"low"], i), At(quote[@"close"], i));
            if (candle) {
                [candles addObject:candle];
            }
        }
    }
    return candles;
}

- (DesktopQuote *)yahooQuote:(NSDictionary *)result symbol:(NSString *)symbol {
    NSDictionary *meta = Dictionary(result[@"meta"]);
    double price = Number(meta[@"regularMarketPrice"]);
    double timestamp = Number(meta[@"regularMarketTime"]);
    if (!IsPrice(price) || !isfinite(timestamp) || timestamp <= 0) {
        return nil;
    }
    DesktopQuote *quote = [DesktopQuote new];
    quote.symbol = symbol;
    NSString *preset = [DesktopMarketService displayNameForSymbol:symbol];
    quote.name = [preset isEqualToString:symbol] ? (String(meta[@"shortName"]) ?: symbol) : preset;
    quote.price = price;
    quote.previousClose = Number(meta[@"previousClose"]);
    if (!IsPrice(quote.previousClose)) {
        quote.previousClose = Number(meta[@"chartPreviousClose"]);
    }
    quote.dayHigh = Number(meta[@"regularMarketDayHigh"]);
    quote.dayLow = Number(meta[@"regularMarketDayLow"]);
    quote.currency = [String(meta[@"instrumentType"]) isEqualToString:@"INDEX"]
        ? @"点" : (String(meta[@"currency"]) ?: @"");
    quote.time = [NSDate dateWithTimeIntervalSince1970:timestamp];
    // A market-close or final correction timestamp can follow the last regular bar.
    double end = YahooRegularSessionEnd(meta);
    if (isfinite(end) && timestamp >= end) {
        quote.minute = [NSDate dateWithTimeIntervalSince1970:end - 60];
    } else {
        quote.minute = MinuteStart(quote.time);
    }
    double precision = Number(meta[@"priceHint"]);
    quote.precision = isfinite(precision) && precision >= 0 && precision <= 8 ? (NSInteger)precision : 2;
    NSString *exchange = String(meta[@"exchangeName"]);
    if ([symbol isEqualToString:FuturesSymbol] || [exchange isEqualToString:@"CME"]) {
        quote.delayMinutes = 10;
    } else if ([exchange isEqualToString:@"SHH"] || [exchange isEqualToString:@"SHZ"]) {
        quote.delayMinutes = 30;
    }
    quote.source = @"Yahoo 财经";
    return quote;
}

- (DesktopQuote *)sinaQuote:(NSData *)data symbol:(NSString *)symbol {
    NSStringEncoding encoding = CFStringConvertEncodingToNSStringEncoding(kCFStringEncodingGB_18030_2000);
    NSString *body = [[NSString alloc] initWithData:data ?: [NSData data] encoding:encoding];
    NSArray *fields = [At([body componentsSeparatedByString:@"\""], 1) componentsSeparatedByString:@","];
    BOOL domestic = IsShanghaiIndex(symbol);
    double price = Number(At(fields, domestic ? 3 : 0));
    NSString *date = At(fields, domestic ? 30 : 12);
    NSString *clock = At(fields, domestic ? 31 : 6);
    NSDateFormatter *formatter = ShanghaiFormatter(@"yyyy-MM-dd HH:mm:ss");
    NSDate *time = [formatter dateFromString:[NSString stringWithFormat:@"%@ %@", date, clock]];
    if (!IsPrice(price) || !time) {
        return nil;
    }

    NSDate *minute = MinuteStart(time);
    if (domestic) {
        NSCalendar *calendar = [[NSCalendar alloc] initWithCalendarIdentifier:NSCalendarIdentifierGregorian];
        calendar.timeZone = formatter.timeZone;
        NSDateComponents *parts = [calendar components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:time];
        NSInteger timeOfDay = parts.hour * 60 + parts.minute;
        if (timeOfDay < 570) {
            minute = nil;
        } else if (timeOfDay >= 900 || (timeOfDay >= 690 && timeOfDay < 780)) {
            // The quote page may publish closing snapshots during the break.
            NSInteger lastTradingMinute = timeOfDay >= 900 ? 899 : 689;
            minute = [minute dateByAddingTimeInterval:(lastTradingMinute - timeOfDay) * 60];
        }
    }

    DesktopQuote *quote = [DesktopQuote new];
    quote.symbol = symbol;
    quote.name = [DesktopMarketService displayNameForSymbol:symbol];
    quote.currency = [symbol isEqualToString:GoldSymbol] ? @"USD/盎司" : @"点";
    quote.source = @"新浪财经 · 延迟未公布";
    quote.time = time;
    quote.minute = minute;
    quote.price = price;
    quote.previousClose = Number(At(fields, domestic ? 2 : 7));
    quote.dayHigh = Number(At(fields, 4));
    quote.dayLow = Number(At(fields, 5));
    quote.precision = 2;
    return quote;
}

- (DesktopQuote *)bankGoldQuote:(NSData *)data {
    NSDictionary *payload = Dictionary(Dictionary(Dictionary(JSON(data))[@"resultData"])[@"datas"]);
    double price = Number(payload[@"price"]);
    double epochMilliseconds = Number(payload[@"time"]);
    if (![String(payload[@"productSku"]) isEqualToString:JDBankGoldSKU] || !IsPrice(price) ||
        !isfinite(epochMilliseconds) || epochMilliseconds <= 0) {
        return nil;
    }
    DesktopQuote *quote = [DesktopQuote new];
    quote.symbol = BankGoldSymbol;
    quote.name = [DesktopMarketService displayNameForSymbol:BankGoldSymbol];
    quote.currency = @"元/克";
    quote.source = @"京东金融 · 客户买入价";
    quote.time = [NSDate dateWithTimeIntervalSince1970:epochMilliseconds / 1000];
    quote.minute = MinuteStart(quote.time);
    quote.price = price;
    quote.previousClose = Number(payload[@"yesterdayPrice"]);
    quote.dayHigh = NAN;
    quote.dayLow = NAN;
    quote.precision = 2;
    return quote;
}

- (void)fetchQuote:(NSString *)symbol completion:(void (^)(DesktopQuote *, NSArray<DesktopCandle *> *))completion {
    NSString *sinaSymbol = SinaSymbols()[symbol];
    if (sinaSymbol) {
        NSString *url = [NSString stringWithFormat:@"https://hq.sinajs.cn/?_=%lld&list=%@",
                         (long long)(NSDate.date.timeIntervalSince1970 * 1000), sinaSymbol];
        [self get:url referer:SinaReferer completion:^(NSData *data) {
            DesktopQuote *quote = [self sinaQuote:data symbol:symbol];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(quote, @[]); });
        }];
        return;
    }
    if ([symbol isEqualToString:BankGoldSymbol]) {
        NSString *url = [@"https://api.jdjygold.com/gw2/generic/jrm/h5/m/stdLatestPrice?productSku=" stringByAppendingString:JDBankGoldSKU];
        [self get:url referer:@"https://www.jd.com/" completion:^(NSData *data) {
            DesktopQuote *quote = [self bankGoldQuote:data];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(quote, @[]); });
        }];
        return;
    }
    [self yahooResponse:symbol daily:NO completion:^(NSDictionary *result) {
        DesktopQuote *quote = [self yahooQuote:result symbol:symbol];
        NSArray *candles = [self yahooCandles:result daily:NO];
        dispatch_async(dispatch_get_main_queue(), ^{ completion(quote, candles); });
    }];
}

static NSArray<DesktopCandle *> *ParseCandles(id rows, NSString *dateFormat, NSArray<NSString *> *keys,
                                              NSTimeInterval offset) {
    if (![rows isKindOfClass:NSArray.class]) {
        return @[];
    }
    NSArray *items = rows;
    NSDateFormatter *formatter = ShanghaiFormatter(dateFormat);
    NSMutableArray<DesktopCandle *> *candles = [NSMutableArray array];
    NSUInteger first = items.count > 300 ? items.count - 300 : 0;
    for (NSUInteger i = first; i < items.count; i++) {
        NSDictionary *row = Dictionary(items[i]);
        NSString *date = String(row[keys[0]]);
        if (!date.length) {
            continue;
        }
        NSDate *time = [[formatter dateFromString:date] dateByAddingTimeInterval:offset];
        DesktopCandle *candle = Candle(time, row[keys[1]], row[keys[2]], row[keys[3]], row[keys[4]]);
        if (candle) {
            [candles addObject:candle];
        }
    }
    return candles;
}

static id JSONPArray(NSData *data) {
    if (!data.length) {
        return nil;
    }
    NSString *body = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRange start = [body rangeOfString:@"(["];
    NSRange end = [body rangeOfString:@"])" options:NSBackwardsSearch];
    if (!body || start.location == NSNotFound || end.location == NSNotFound || end.location <= start.location) {
        return nil;
    }
    NSRange range = NSMakeRange(start.location + 1, end.location - start.location);
    return JSON([[body substringWithRange:range] dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)fetchBankGoldCandlesDaily:(BOOL)daily completion:(void (^)(NSArray<DesktopCandle *> *))completion {
    NSDateFormatter *formatter = ShanghaiFormatter(@"yyyy-MM-dd'T'HH:mm:ss");
    NSDictionary *parameters = @{@"productSku": JDBankGoldSKU, @"barCount": @120, @"kType": daily ? @"day" : @"m1",
                                 @"from": [formatter stringFromDate:NSDate.date], @"withHistory": @YES, @"source": @"gold-chart"};
    NSData *json = [NSJSONSerialization dataWithJSONObject:parameters options:0 error:NULL];
    NSString *value = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    NSString *form = [@"reqData=" stringByAppendingString:PathSymbol(value)];
    NSURL *url = [NSURL URLWithString:@"https://api.jdjygold.com/gw2/generic/hj/h5/m/getKlineAndIndicators"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    request.HTTPBody = [form dataUsingEncoding:NSUTF8StringEncoding];
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"https://m.jdjygold.com/" forHTTPHeaderField:@"Referer"];
    [request setValue:@"https://m.jdjygold.com" forHTTPHeaderField:@"Origin"];
    [self send:request completion:^(NSData *data) {
        NSDictionary *payload = Dictionary(Dictionary(Dictionary(JSON(data))[@"resultData"])[@"data"]);
        NSArray<DesktopCandle *> *candles = ParseCandles(payload[@"dots"] ?: payload[@"dotDos"],
            @"yyyy-MM-dd'T'HH:mm:ss", @[@"tradeDateTime", @"openPrice", @"highPrice", @"lowPrice", @"closePrice"], 0);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(candles); });
    }];
}

- (void)fetchCandles:(NSString *)symbol daily:(BOOL)daily completion:(void (^)(NSArray<DesktopCandle *> *))completion {
    NSString *sinaSymbol = SinaSymbols()[symbol];
    if ([symbol isEqualToString:BankGoldSymbol]) {
        [self fetchBankGoldCandlesDaily:daily completion:completion];
    } else if (IsShanghaiIndex(symbol)) {
        NSString *url = [NSString stringWithFormat:@"https://quotes.sina.cn/cn/api/openapi.php/CN_MarketDataService.getKLineData?symbol=%@&scale=%@&ma=no&datalen=150", sinaSymbol, daily ? @"240" : @"1"];
        [self get:url referer:SinaReferer completion:^(NSData *data) {
            id rows = Dictionary(Dictionary(JSON(data))[@"result"])[@"data"];
            NSArray<DesktopCandle *> *candles = ParseCandles(rows, daily ? @"yyyy-MM-dd" : @"yyyy-MM-dd HH:mm:ss",
                @[@"day", @"open", @"high", @"low", @"close"], daily ? 0 : -60);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(candles); });
        }];
    } else if (sinaSymbol) {
        NSString *base = daily
            ? @"https://stock2.finance.sina.com.cn/futures/api/jsonp.php/var=/GlobalFuturesService.getGlobalFuturesDailyKLine?symbol="
            : @"https://gu.sina.cn/ft/api/jsonp.php/var%20_x=/GlobalService.getMink?type=1&symbol=";
        NSString *url = [base stringByAppendingString:[sinaSymbol substringFromIndex:3]];
        [self get:url referer:SinaReferer completion:^(NSData *data) {
            NSArray *keys = daily ? @[@"date", @"open", @"high", @"low", @"close"] : @[@"d", @"o", @"h", @"l", @"c"];
            NSArray<DesktopCandle *> *candles = ParseCandles(JSONPArray(data), daily ? @"yyyy-MM-dd" : @"yyyy-MM-dd HH:mm:ss",
                                                             keys, daily ? 0 : -60);
            dispatch_async(dispatch_get_main_queue(), ^{ completion(candles); });
        }];
    } else {
        [self yahooResponse:symbol daily:daily completion:^(NSDictionary *result) {
            NSArray *candles = [self yahooCandles:result daily:daily];
            dispatch_async(dispatch_get_main_queue(), ^{ completion(candles); });
        }];
    }
}
@end
