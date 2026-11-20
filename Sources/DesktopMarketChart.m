#import "DesktopMarketChart.h"
#import "DesktopMarketService.h"
#import <math.h>

NSColor *DesktopColor(unsigned int rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                               green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

static NSUInteger const InitialVisibleCandles = 120;

@implementation DesktopMarketChart {
    NSInteger _hovered;
    NSTrackingArea *_tracking;
    NSUInteger _visibleLimit;
    NSDate *_rightEdgeTime;
    NSDate *_dragEdgeTime;
    CGFloat _dragStartX;
    BOOL _dragging;
    CGFloat _scrollRemainder;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _hovered = -1;
        _candles = @[];
        _dailyReferences = @[];
        _precision = 2;
        _visibleLimit = InitialVisibleCandles;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityImageRole];
        [self setAccessibilityLabel:@"价格图表"];
    }
    return self;
}

- (void)setCandles:(NSArray<DesktopCandle *> *)candles {
    _candles = [candles copy];
    if (!_candles.count && !self.miniature) {
        [self setAccessibilityValue:nil];
    }
    self.needsDisplay = YES;
}

- (NSUInteger)endIndexAtTime:(NSDate *)time {
    NSUInteger lower = 0, upper = self.candles.count;
    while (lower < upper) {
        NSUInteger mid = lower + (upper - lower) / 2;
        if ([self.candles[mid].time compare:time] == NSOrderedDescending) {
            upper = mid;
        } else {
            lower = mid + 1;
        }
    }
    return lower;
}

- (NSRange)visibleCandleRange {
    NSUInteger total = self.candles.count;
    if (self.miniature) {
        return NSMakeRange(0, total);
    }
    NSUInteger length = MIN(total, _visibleLimit);
    NSUInteger end = _rightEdgeTime ? [self endIndexAtTime:_rightEdgeTime] : total;
    return NSMakeRange(MAX(length, end) - length, length);
}

- (void)showLatest {
    _rightEdgeTime = nil;
    _hovered = -1;
    _scrollRemainder = 0;
    self.needsDisplay = YES;
}

- (void)resetViewport {
    _visibleLimit = InitialVisibleCandles;
    [self showLatest];
}

- (void)moveRightEdgeToIndex:(NSInteger)index {
    NSInteger total = (NSInteger)self.candles.count;
    NSInteger minimum = MIN(total, (NSInteger)_visibleLimit);
    NSInteger end = MAX(minimum, MIN(total, index));
    _rightEdgeTime = end < total ? self.candles[(NSUInteger)end - 1].time : nil;
    self.needsDisplay = YES;
}

- (void)updateTrackingAreas {
    [super updateTrackingAreas];
    if (_tracking) {
        [self removeTrackingArea:_tracking];
        _tracking = nil;
    }
    if (!self.miniature) {
        _tracking = [[NSTrackingArea alloc] initWithRect:NSZeroRect
                                                options:NSTrackingMouseMoved | NSTrackingMouseEnteredAndExited |
                                                        NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect
                                                  owner:self userInfo:nil];
        [self addTrackingArea:_tracking];
    }
}

- (NSRect)plot {
    NSRect bounds = self.bounds;
    return self.miniature ? NSInsetRect(bounds, 2, 4) : NSMakeRect(12, 32, NSWidth(bounds) - 96, NSHeight(bounds) - 84);
}

- (void)updateHoverAtPoint:(NSPoint)point {
    NSRect plot = [self plot];
    NSRange visible = self.visibleCandleRange;
    _hovered = -1;
    if (visible.length && NSPointInRect(point, plot)) {
        CGFloat fraction = (point.x - NSMinX(plot)) / NSWidth(plot);
        _hovered = (NSInteger)MIN(visible.length - 1, (NSUInteger)(fraction * visible.length));
    }
    self.needsDisplay = YES;
}

- (void)mouseMoved:(NSEvent *)event {
    [self updateHoverAtPoint:[self convertPoint:event.locationInWindow fromView:nil]];
}

- (void)mouseEntered:(NSEvent *)event {
    [self mouseMoved:event];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    _hovered = -1;
    self.needsDisplay = YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRange visible = self.visibleCandleRange;
    _dragging = !self.miniature && visible.length && NSPointInRect(point, [self plot]);
    if (_dragging) {
        _dragStartX = point.x;
        _dragEdgeTime = self.candles[NSMaxRange(visible) - 1].time;
        [NSCursor.closedHandCursor set];
        [self updateHoverAtPoint:point];
    }
}

- (void)mouseDragged:(NSEvent *)event {
    if (!_dragging) {
        return;
    }
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat width = NSWidth([self plot]);
    if (width > 0) {
        NSInteger bars = lround((point.x - _dragStartX) * self.visibleCandleRange.length / width);
        [self moveRightEdgeToIndex:(NSInteger)[self endIndexAtTime:_dragEdgeTime] - bars];
        [self updateHoverAtPoint:point];
    }
}

- (void)mouseUp:(NSEvent *)event {
    if (_dragging) {
        _dragging = NO;
        _dragEdgeTime = nil;
        [NSCursor.arrowCursor set];
        [self mouseMoved:event];
    }
}

- (void)scrollWheel:(NSEvent *)event {
    NSRange visible = self.visibleCandleRange;
    NSRect plot = [self plot];
    if (self.miniature || !visible.length || NSWidth(plot) <= 0) {
        [super scrollWheel:event];
        return;
    }

    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    CGFloat dx = event.scrollingDeltaX, dy = event.scrollingDeltaY;
    if (fabs(dx) > fabs(dy)) {
        CGFloat scale = event.hasPreciseScrollingDeltas ? visible.length / NSWidth(plot) : 3.0;
        _scrollRemainder += dx * scale;
        NSInteger bars = (NSInteger)_scrollRemainder;
        _scrollRemainder -= bars;
        [self moveRightEdgeToIndex:(NSInteger)NSMaxRange(visible) - bars];
    } else if (dy) {
        double scale = exp(-dy * (event.hasPreciseScrollingDeltas ? 0.018 : 0.18));
        NSUInteger total = self.candles.count;
        NSUInteger length = (NSUInteger)fmax(MIN(18, total), fmin(total, round(visible.length * scale)));
        if (length != visible.length) {
            CGFloat fraction = fmax(0, fmin(1, (point.x - NSMinX(plot)) / NSWidth(plot)));
            NSInteger end = (NSInteger)NSMaxRange(visible) + lround(((NSInteger)length - (NSInteger)visible.length) * (1 - fraction));
            _visibleLimit = length;
            [self moveRightEdgeToIndex:end];
        }
    }
    [self updateHoverAtPoint:point];
}

static void DrawText(NSString *text, NSPoint point, NSColor *color, CGFloat size) {
    [text drawAtPoint:point withAttributes:@{
        NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:size weight:NSFontWeightRegular],
        NSForegroundColorAttributeName: color
    }];
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    NSRect plot = [self plot];
    if (!self.miniature) {
        [DesktopColor(0x111B2A) setFill];
        [[NSBezierPath bezierPathWithRoundedRect:self.bounds xRadius:12 yRadius:12] fill];
    }
    NSRange visible = self.visibleCandleRange;
    if (!visible.length || NSWidth(plot) <= 0 || NSHeight(plot) <= 0) {
        if (!self.miniature) {
            DrawText(@"暂无 K 线", NSMakePoint(20, NSMidY(self.bounds)), DesktopColor(0x91A1B7), 13);
        }
        return;
    }

    double minimum = INFINITY, maximum = -INFINITY;
    for (NSUInteger i = visible.location; i < NSMaxRange(visible); i++) {
        DesktopCandle *candle = self.candles[i];
        minimum = MIN(minimum, candle.low);
        maximum = MAX(maximum, candle.high);
    }
    double padding = maximum > minimum ? (maximum - minimum) * 0.07 : MAX(maximum * 0.001, 0.0001);
    minimum -= padding;
    maximum += padding;
    CGFloat (^yForPrice)(double) = ^CGFloat(double price) {
        return NSMinY(plot) + (price - minimum) / (maximum - minimum) * NSHeight(plot);
    };
    CGFloat step = NSWidth(plot) / visible.length;
    NSColor *muted = DesktopColor(0x91A1B7);
    if (!self.miniature) {
        for (NSInteger i = 0; i <= 4; i++) {
            double level = minimum + (maximum - minimum) * i / 4;
            CGFloat y = yForPrice(level);
            [DesktopColor(0x263449) setStroke];
            [NSBezierPath strokeLineFromPoint:NSMakePoint(NSMinX(plot), y) toPoint:NSMakePoint(NSMaxX(plot), y)];
            DrawText([NSString stringWithFormat:@"%.*f", (int)self.precision, level],
                     NSMakePoint(NSMaxX(plot) + 8, y - 6), muted, 10);
        }
    }

    CGFloat bodyWidth = MAX(1, MIN(self.miniature ? 3 : 8, step * 0.60));
    for (NSUInteger i = 0; i < visible.length; i++) {
        DesktopCandle *candle = self.candles[visible.location + i];
        CGFloat x = NSMinX(plot) + (i + 0.5) * step;
        CGFloat open = yForPrice(candle.open), close = yForPrice(candle.close);
        NSColor *color = DesktopColor(candle.close >= candle.open ? 0xFF7884 : 0x53CDB3);
        [color setStroke];
        [color setFill];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, yForPrice(candle.low)) toPoint:NSMakePoint(x, yForPrice(candle.high))];
        NSRectFill(NSMakeRect(x - bodyWidth / 2, MIN(open, close), bodyWidth, MAX(1, fabs(close - open))));
    }

    if (self.miniature) {
        return;
    }

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = self.daily ? @"yy-MM-dd" : @"MM-dd HH:mm";
    DrawText([formatter stringFromDate:self.candles[visible.location].time], NSMakePoint(NSMinX(plot), 11), muted, 10);
    DrawText([formatter stringFromDate:self.candles[NSMaxRange(visible) - 1].time], NSMakePoint(NSMaxX(plot) - 68, 11), muted, 10);

    BOOL hovering = _hovered >= 0 && (NSUInteger)_hovered < visible.length;
    NSUInteger index = hovering ? visible.location + (NSUInteger)_hovered : NSMaxRange(visible) - 1;
    DesktopCandle *candle = self.candles[index];
    if (hovering) {
        CGFloat x = NSMinX(plot) + (_hovered + 0.5) * step;
        [muted setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, NSMinY(plot)) toPoint:NSMakePoint(x, NSMaxY(plot))];
    }
    int p = (int)self.precision;
    NSString *summary = [NSString stringWithFormat:@"%@   开 %.*f   高 %.*f   低 %.*f   收 %.*f",
                         [formatter stringFromDate:candle.time], p, candle.open, p, candle.high, p, candle.low, p, candle.close];
    BOOL isSettlement = NO;
    double previousClose = DesktopPreviousTradingDayPrice(candle, self.dailyReferences, self.quote, &isSettlement);
    NSString *change = @"涨跌 —  ·  暂无上一交易日参考价";
    NSColor *changeColor = muted;
    if (isfinite(previousClose) && previousClose > 0) {
        double amount = candle.close - previousClose;
        change = [NSString stringWithFormat:@"涨跌 %+.*f（%+.2f%%）  ·  %@ %.*f", p, amount,
                  amount / previousClose * 100, isSettlement ? @"较昨结" : @"较昨收", p, previousClose];
        if (amount) {
            changeColor = DesktopColor(amount > 0 ? 0xFF808A : 0x59D7B9);
        }
    }
    DrawText(summary, NSMakePoint(NSMinX(plot), NSMaxY(plot) + 28), DesktopColor(0xDCE6F5), 11);
    DrawText(change, NSMakePoint(NSMinX(plot), NSMaxY(plot) + 10), changeColor, 11);
    [self setAccessibilityValue:[NSString stringWithFormat:@"%@，%@", summary, change]];
}
@end
