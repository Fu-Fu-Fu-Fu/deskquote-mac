#import "DesktopMarketChart.h"
#import "DesktopMarketService.h"

NSColor *DesktopColor(unsigned int rgb) {
    return [NSColor colorWithSRGBRed:((rgb >> 16) & 255) / 255.0
                               green:((rgb >> 8) & 255) / 255.0 blue:(rgb & 255) / 255.0 alpha:1];
}

@implementation DesktopMarketChart {
    NSInteger _hovered;
    NSTrackingArea *_tracking;
}

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        _hovered = -1;
        _candles = @[];
        _precision = 2;
        [self setAccessibilityElement:YES];
        [self setAccessibilityRole:NSAccessibilityImageRole];
        [self setAccessibilityLabel:@"价格图表"];
    }
    return self;
}

- (void)setCandles:(NSArray<DesktopCandle *> *)candles {
    _candles = [candles copy];
    if (_hovered >= (NSInteger)_candles.count) {
        _hovered = -1;
    }
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
    return self.miniature ? NSInsetRect(bounds, 2, 4) : NSMakeRect(12, 32, NSWidth(bounds) - 96, NSHeight(bounds) - 64);
}

- (void)mouseMoved:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect plot = [self plot];
    _hovered = -1;
    if (self.candles.count && NSPointInRect(point, plot)) {
        CGFloat fraction = (point.x - NSMinX(plot)) / NSWidth(plot);
        _hovered = MIN((NSInteger)self.candles.count - 1, (NSInteger)(fraction * self.candles.count));
    }
    self.needsDisplay = YES;
}

- (void)mouseEntered:(NSEvent *)event {
    [self mouseMoved:event];
}

- (void)mouseExited:(NSEvent *)event {
    (void)event;
    _hovered = -1;
    self.needsDisplay = YES;
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
    if (self.candles.count == 0 || NSWidth(plot) <= 0 || NSHeight(plot) <= 0) {
        if (!self.miniature) {
            DrawText(@"暂无 K 线", NSMakePoint(20, NSMidY(self.bounds)), DesktopColor(0x91A1B7), 13);
        }
        return;
    }

    double minimum = INFINITY, maximum = -INFINITY;
    for (DesktopCandle *candle in self.candles) {
        minimum = MIN(minimum, candle.low);
        maximum = MAX(maximum, candle.high);
    }
    double padding = maximum > minimum ? (maximum - minimum) * 0.07 : MAX(maximum * 0.001, 0.0001);
    minimum -= padding;
    maximum += padding;
    CGFloat (^yForPrice)(double) = ^CGFloat(double price) {
        return NSMinY(plot) + (price - minimum) / (maximum - minimum) * NSHeight(plot);
    };
    CGFloat step = NSWidth(plot) / self.candles.count;
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
    for (NSUInteger i = 0; i < self.candles.count; i++) {
        DesktopCandle *candle = self.candles[i];
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
    formatter.dateFormat = self.daily ? @"MM-dd" : @"MM-dd HH:mm";
    DrawText([formatter stringFromDate:self.candles.firstObject.time], NSMakePoint(NSMinX(plot), 11), muted, 10);
    DrawText([formatter stringFromDate:self.candles.lastObject.time], NSMakePoint(NSMaxX(plot) - 66, 11), muted, 10);

    if (_hovered >= 0 && _hovered < (NSInteger)self.candles.count) {
        DesktopCandle *candle = self.candles[_hovered];
        CGFloat x = NSMinX(plot) + (_hovered + 0.5) * step;
        [muted setStroke];
        [NSBezierPath strokeLineFromPoint:NSMakePoint(x, NSMinY(plot)) toPoint:NSMakePoint(x, NSMaxY(plot))];
        int p = (int)self.precision;
        NSString *summary = [NSString stringWithFormat:@"%@   开 %.*f   高 %.*f   低 %.*f   收 %.*f",
                             [formatter stringFromDate:candle.time], p, candle.open, p, candle.high, p, candle.low, p, candle.close];
        DrawText(summary, NSMakePoint(NSMinX(plot), NSMaxY(plot) + 12), DesktopColor(0xDCE6F5), 11);
    }
}
@end
