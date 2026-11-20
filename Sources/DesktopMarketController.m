#import "DesktopMarketController.h"
#import "DesktopMarketChart.h"
#import "DesktopMarketService.h"
#import <math.h>

static NSString * const SymbolsKey = @"desktopMarket.symbols.v1";
static NSString * const AddedMarketsKey = @"desktopMarket.addedMarkets.v2";
static NSString * const VisibleKey = @"desktopMarket.visible.v1";
static NSString * const PinnedKey = @"desktopMarket.pinned.v1";
static NSString * const PanelFrame = @"DesktopMarketPanel";
static NSString * const FloatingPanelFrame = @"DesktopMarketFloatingPanel";
static NSTimeInterval const TimerInterval = 5;
static NSTimeInterval const MinuteHistoryInterval = 30;
static CGFloat const Width = 370;
static CGFloat const RowHeight = 66;

static NSPoint ScreenPointForEvent(NSEvent *event) {
    return event.window ? [event.window convertPointToScreen:event.locationInWindow] : event.locationInWindow;
}

@interface DesktopMarketHeader : NSView
@end

@implementation DesktopMarketHeader
- (NSView *)hitTest:(NSPoint)point {
    return [super hitTest:point] ? self : nil;
}

- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    if (window.level == NSFloatingWindowLevel) {
        [window performWindowDragWithEvent:event];
        return;
    }
    NSPoint start = ScreenPointForEvent(event);
    NSPoint origin = window.frame.origin;
    while (YES) {
        NSEvent *next = [window nextEventMatchingMask:NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp];
        if (!next || next.type == NSEventTypeLeftMouseUp) {
            return;
        }
        NSPoint location = ScreenPointForEvent(next);
        [window setFrameOrigin:NSMakePoint(origin.x + location.x - start.x, origin.y + location.y - start.y)];
    }
}
@end

@class DesktopMarketRowButton;

@protocol DesktopMarketRowDragDelegate <NSObject>
- (void)rowButton:(DesktopMarketRowButton *)button draggedToPoint:(NSPoint)point;
- (void)rowButton:(DesktopMarketRowButton *)button finishedAtPoint:(NSPoint)point commit:(BOOL)commit;
@end

@interface DesktopMarketRowButton : NSButton
@property (nonatomic, weak) id<DesktopMarketRowDragDelegate> dragDelegate;
@end

@implementation DesktopMarketRowButton
- (BOOL)mouseDownCanMoveWindow {
    return NO;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    (void)event;
    return YES;
}

- (void)mouseDown:(NSEvent *)event {
    NSWindow *window = self.window;
    if (!self.dragDelegate || !window || !self.enabled) {
        [super mouseDown:event];
        return;
    }

    NSView *row = self.superview;
    NSPoint start = event.locationInWindow;
    NSPoint point = start;
    BOOL dragging = NO;
    NSEventMask mask = NSEventMaskLeftMouseDragged | NSEventMaskLeftMouseUp | NSEventMaskKeyDown;
    while (self.window == window) {
        NSDate *until = dragging ? [NSDate dateWithTimeIntervalSinceNow:0.08] : NSDate.distantFuture;
        NSEvent *next = [NSApp nextEventMatchingMask:mask untilDate:until inMode:NSEventTrackingRunLoopMode dequeue:YES];
        if (next) {
            point = [window convertPointFromScreen:ScreenPointForEvent(next)];
        }
        if (next.type == NSEventTypeKeyDown && next.keyCode == 53) {
            break;
        }
        if (next.type == NSEventTypeLeftMouseUp) {
            if (dragging) {
                [self.dragDelegate rowButton:self finishedAtPoint:point commit:YES];
                [NSCursor pop];
                row.alphaValue = 1;
            } else if (NSPointInRect([self convertPoint:point fromView:nil], self.bounds)) {
                [self performClick:nil];
            }
            return;
        }
        if (!dragging && next.type == NSEventTypeLeftMouseDragged &&
            hypot(point.x - start.x, point.y - start.y) >= 4) {
            dragging = YES;
            row.alphaValue = 0.48;
            [NSCursor.closedHandCursor push];
        }
        if (dragging) {
            [self.dragDelegate rowButton:self draggedToPoint:point];
        }
    }
    if (dragging) {
        [self.dragDelegate rowButton:self finishedAtPoint:NSZeroPoint commit:NO];
        [NSCursor pop];
        row.alphaValue = 1;
    }
}
@end

@interface DesktopMarketRow : NSView
@property (nonatomic, strong) NSTextField *nameLabel;
@property (nonatomic, strong) NSTextField *metaLabel;
@property (nonatomic, strong) NSTextField *priceLabel;
@property (nonatomic, strong) NSTextField *changeLabel;
@property (nonatomic, strong) DesktopMarketChart *chart;
@property (nonatomic, strong) DesktopMarketRowButton *button;
@end

@implementation DesktopMarketRow
- (NSMenu *)menuForEvent:(NSEvent *)event {
    (void)event;
    return self.menu;
}
@end

@interface DesktopMarketController () <NSWindowDelegate, DesktopMarketRowDragDelegate>
@end

static NSTextField *Label(CGFloat size, NSFontWeight weight, unsigned int color) {
    NSTextField *label = [NSTextField labelWithString:@""];
    label.font = [NSFont systemFontOfSize:size weight:weight];
    label.textColor = DesktopColor(color);
    label.lineBreakMode = NSLineBreakByTruncatingTail;
    label.maximumNumberOfLines = 1;
    return label;
}

static NSButton *Button(NSString *title, NSString *tip, id target, SEL action, NSRect frame) {
    NSButton *button = [NSButton buttonWithTitle:title target:target action:action];
    button.frame = frame;
    button.bezelStyle = NSBezelStyleRounded;
    button.controlSize = NSControlSizeSmall;
    button.toolTip = tip;
    [button setAccessibilityLabel:tip];
    return button;
}

static void Place(NSView *view, NSView *parent, NSRect rect) {
    view.frame = rect;
    [parent addSubview:view];
}

static NSString *Price(double value, NSInteger precision) {
    if (!isfinite(value)) {
        return @"—";
    }
    NSNumberFormatter *formatter = [NSNumberFormatter new];
    formatter.numberStyle = NSNumberFormatterDecimalStyle;
    formatter.minimumFractionDigits = (NSUInteger)precision;
    formatter.maximumFractionDigits = (NSUInteger)precision;
    return [formatter stringFromNumber:@(value)] ?: @"—";
}

static NSString *Delta(DesktopQuote *quote) {
    if (!quote || !isfinite(quote.changePercent)) {
        return @"—";
    }
    return [NSString stringWithFormat:@"%+.*f  (%+.2f%%)", (int)quote.precision, quote.change, quote.changePercent];
}

static NSColor *Trend(DesktopQuote *quote) {
    double change = quote ? quote.change : NAN;
    if (!isfinite(change) || change == 0) {
        return DesktopColor(0x9DACC1);
    }
    return DesktopColor(change > 0 ? 0xFF808A : 0x59D7B9);
}

static NSString *TimeLabel(NSDate *time, NSString *format) {
    if (!time) {
        return @"";
    }
    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = format;
    return [formatter stringFromDate:time];
}

@implementation DesktopMarketController {
    DesktopMarketService *_service;
    NSMutableArray<NSString *> *_symbols;
    NSMutableDictionary<NSString *, DesktopQuote *> *_quotes;
    NSMutableDictionary<NSString *, NSArray<DesktopCandle *> *> *_intraday;
    NSMutableDictionary<NSString *, DesktopMarketRow *> *_rows;
    NSMutableDictionary<NSString *, NSUUID *> *_requests;
    NSMutableSet<NSString *> *_failed;
    NSMutableSet<NSString *> *_adding;
    NSMutableDictionary<NSString *, NSDate *> *_lastQuoteAttempts;
    NSMutableDictionary<NSString *, NSDate *> *_lastHistoryAttempts;
    NSMutableDictionary<NSString *, NSUUID *> *_historyRequests;
    NSMutableSet<NSString *> *_minuteHistoryFailures;
    NSTimer *_timer;

    NSPanel *_panel;
    NSPanel *_homePanel;
    NSPanel *_floatingPanel;
    NSView *_panelContent;
    NSScrollView *_scroll;
    NSTextField *_status;
    NSButton *_pin;
    NSButton *_menuButton;
    NSView *_dropLine;
    BOOL _positioningPanel;
    BOOL _manualRefreshPending;
    NSDate *_lastManualRefresh;

    NSWindow *_detail;
    NSString *_detailSymbol;
    NSTextField *_detailPrice;
    NSTextField *_detailMeta;
    NSTextField *_detailStats;
    NSTextField *_detailStatus;
    NSSegmentedControl *_range;
    DesktopMarketChart *_chart;
    NSArray<DesktopCandle *> *_detailMinuteHistory;
    NSDate *_detailMinuteCheckedAt;
    BOOL _detailMinuteLoading;
    BOOL _detailMinuteFailed;
    NSArray<DesktopCandle *> *_dailyCandles;
    NSDate *_dailyCheckedAt;
    BOOL _chartFailed;
    NSUInteger _detailGeneration;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _service = [DesktopMarketService new];
        _symbols = [NSMutableArray array];
        _quotes = [NSMutableDictionary dictionary];
        _intraday = [NSMutableDictionary dictionary];
        _rows = [NSMutableDictionary dictionary];
        _requests = [NSMutableDictionary dictionary];
        _failed = [NSMutableSet set];
        _adding = [NSMutableSet set];
        _lastQuoteAttempts = [NSMutableDictionary dictionary];
        _lastHistoryAttempts = [NSMutableDictionary dictionary];
        _historyRequests = [NSMutableDictionary dictionary];
        _minuteHistoryFailures = [NSMutableSet set];
        NSArray *stored = [NSUserDefaults.standardUserDefaults arrayForKey:SymbolsKey];
        for (id item in stored ?: DesktopMarketService.defaultSymbols) {
            if (![item isKindOfClass:NSString.class]) {
                continue;
            }
            NSString *symbol = [DesktopMarketService normalizedSymbol:item];
            if (symbol && ![_symbols containsObject:symbol]) {
                [_symbols addObject:symbol];
            }
        }
        if (![NSUserDefaults.standardUserDefaults boolForKey:AddedMarketsKey]) {
            for (NSString *symbol in DesktopMarketService.addedMarketSymbols) {
                if (![_symbols containsObject:symbol]) {
                    [_symbols addObject:symbol];
                }
            }
            [self saveSymbols];
            [NSUserDefaults.standardUserDefaults setBool:YES forKey:AddedMarketsKey];
        }
    }
    return self;
}

- (void)restoreIfVisible {
    NSNumber *visible = [NSUserDefaults.standardUserDefaults objectForKey:VisibleKey];
    if (!visible || visible.boolValue) {
        [self showPanel];
    }
}

- (void)toggle {
    if (_panel.isVisible && (_panel != _homePanel || _homePanel.isOnActiveSpace)) {
        [_panel close];
    } else {
        [self showPanel];
        if (_panel == _homePanel && !_homePanel.isOnActiveSpace) {
            [_homePanel makeKeyAndOrderFront:nil];
        }
    }
}

- (void)showPanel {
    if (!_panel) {
        [self buildPanel];
    }
    [self keepHomePanelOnPrimaryScreen];
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:VisibleKey];
    [_panel orderFrontRegardless];
    [self updateTimer];
    [self refresh];
}

- (void)updateTimer {
    BOOL needed = _panel.isVisible || _detail.isVisible;
    if (needed && !_timer) {
        __weak DesktopMarketController *weakSelf = self;
        _timer = [NSTimer timerWithTimeInterval:TimerInterval repeats:YES block:^(NSTimer *timer) {
            (void)timer;
            [weakSelf refreshQuotesForcing:NO];
        }];
        _timer.tolerance = 0.4;
        [[NSRunLoop mainRunLoop] addTimer:_timer forMode:NSRunLoopCommonModes];
    } else if (!needed) {
        [_timer invalidate];
        _timer = nil;
    }
}

- (NSPanel *)makePanelPinned:(BOOL)pinned {
    NSPanel *panel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, Width, 280)
                                                styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                          NSWindowStyleMaskFullSizeContentView
                                                  backing:NSBackingStoreBuffered defer:NO];
    panel.releasedWhenClosed = NO;
    panel.title = @"StockBar 桌面行情";
    panel.titleVisibility = NSWindowTitleHidden;
    panel.titlebarAppearsTransparent = YES;
    panel.movable = pinned;
    panel.movableByWindowBackground = NO;
    panel.hidesOnDeactivate = NO;
    panel.animationBehavior = NSWindowAnimationBehaviorNone;
    [panel standardWindowButton:NSWindowCloseButton].hidden = YES;
    [panel standardWindowButton:NSWindowMiniaturizeButton].hidden = YES;
    [panel standardWindowButton:NSWindowZoomButton].hidden = YES;
    panel.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    panel.backgroundColor = DesktopColor(0x0D1420);
    panel.level = pinned ? NSFloatingWindowLevel : NSNormalWindowLevel;
    panel.collectionBehavior = pinned
        ? NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorFullScreenAuxiliary
        : NSWindowCollectionBehaviorManaged | NSWindowCollectionBehaviorFullScreenNone | NSWindowCollectionBehaviorIgnoresCycle;

    // The first screen is the system's primary display. mainScreen can follow the key window.
    NSRect desktop = NSScreen.screens.firstObject.visibleFrame;
    [panel setFrameTopLeftPoint:NSMakePoint(NSMaxX(desktop) - Width - 26, NSMaxY(desktop) - 30)];
    NSString *frameName = pinned ? FloatingPanelFrame : PanelFrame;
    [panel setFrameUsingName:frameName];
    [panel setFrameAutosaveName:frameName];
    return panel;
}

- (void)buildPanel {
    _homePanel = [self makePanelPinned:NO];
    _homePanel.delegate = self;
    _panel = _homePanel;
    _panelContent = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, Width, 280)];
    _panel.contentView = _panelContent;
    [self buildPanelControls];
    [self rebuildRows];
    if ([NSUserDefaults.standardUserDefaults boolForKey:PinnedKey]) {
        [self switchPanelPinned:YES];
    }
    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(screenParametersChanged:)
                                               name:NSApplicationDidChangeScreenParametersNotification object:NSApp];
}

- (void)screenParametersChanged:(NSNotification *)notification {
    (void)notification;
    [self keepHomePanelOnPrimaryScreen];
    if (_panel == _homePanel) {
        [self resizePanelForRows];
    }
}

- (void)keepHomePanelOnPrimaryScreen {
    NSScreen *screen = NSScreen.screens.firstObject;
    if (!_homePanel || !screen || _positioningPanel) {
        return;
    }
    NSRect desktop = screen.visibleFrame;
    NSRect frame = _homePanel.frame;
    NSPoint origin = frame.origin;
    if (!NSIntersectsRect(frame, desktop)) {
        origin = NSMakePoint(NSMaxX(desktop) - NSWidth(frame) - 26,
                             NSMaxY(desktop) - NSHeight(frame) - 30);
    }
    origin.x = fmax(NSMinX(desktop), fmin(origin.x, NSMaxX(desktop) - NSWidth(frame)));
    origin.y = fmax(NSMinY(desktop), fmin(origin.y, NSMaxY(desktop) - NSHeight(frame)));
    if (!NSEqualPoints(origin, frame.origin)) {
        _positioningPanel = YES;
        [_homePanel setFrameOrigin:origin];
        _positioningPanel = NO;
    }
}

- (void)buildPanelControls {
    DesktopMarketHeader *header = [[DesktopMarketHeader alloc] initWithFrame:NSMakeRect(0, 229, 186, 50)];
    header.autoresizingMask = NSViewMinYMargin;
    [_panelContent addSubview:header];
    NSTextField *title = Label(20, NSFontWeightBold, 0xF0F5FC);
    title.stringValue = @"桌面行情";
    Place(title, header, NSMakeRect(18, 8, 140, 28));

    NSButton *add = Button(@"＋", @"添加自选", self, @selector(addSymbol:), NSMakeRect(190, 239, 33, 24));
    NSButton *refresh = Button(@"刷新", @"立即刷新行情", self, @selector(refreshAction:), NSMakeRect(226, 239, 40, 24));
    _pin = Button(@"置顶", @"切换悬浮置顶", self, @selector(togglePin:), NSMakeRect(269, 239, 51, 24));
    _menuButton = Button(@"⋯", @"行情窗选项", self, @selector(showOptions:), NSMakeRect(324, 239, 29, 24));
    for (NSButton *button in @[add, refresh, _pin, _menuButton]) {
        [_panelContent addSubview:button];
        button.autoresizingMask = NSViewMinYMargin;
    }

    _scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 37, Width - 24, 192)];
    _scroll.drawsBackground = NO;
    _scroll.borderType = NSNoBorder;
    _scroll.autohidesScrollers = YES;
    _scroll.scrollerStyle = NSScrollerStyleOverlay;
    _scroll.autoresizingMask = NSViewHeightSizable;
    [_panelContent addSubview:_scroll];

    _status = Label(10, NSFontWeightMedium, 0x95A7BF);
    Place(_status, _panelContent, NSMakeRect(18, 11, Width - 36, 15));
}

- (NSUInteger)visibleRowCount {
    NSScreen *screen = _panel == _homePanel ? NSScreen.screens.firstObject : _panel.screen;
    NSUInteger capacity = screen ? (NSUInteger)fmax(1, floor((NSHeight(screen.visibleFrame) - 105) / RowHeight)) : 7;
    return MAX(1, MIN(MIN(7, capacity), _symbols.count));
}

- (void)resizePanelForRows {
    NSRect frame = _panel.frame;
    CGFloat height = [self visibleRowCount] * RowHeight + 85;
    [_panel setContentSize:NSMakeSize(Width, height)];
    [_panel setFrameTopLeftPoint:NSMakePoint(NSMinX(frame), NSMaxY(frame))];
    if (_panel == _homePanel) {
        [self keepHomePanelOnPrimaryScreen];
    }
    _scroll.hasVerticalScroller = _symbols.count > [self visibleRowCount];
}

- (void)rebuildRows {
    [self resizePanelForRows];
    CGFloat documentHeight = MAX(1, _symbols.count) * RowHeight;
    NSView *document = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, Width - 24, documentHeight)];
    _scroll.documentView = document;
    _dropLine = [[NSView alloc] initWithFrame:NSZeroRect];
    _dropLine.wantsLayer = YES;
    _dropLine.layer.backgroundColor = DesktopColor(0x88BAFF).CGColor;
    _dropLine.layer.cornerRadius = 1;
    _dropLine.hidden = YES;
    [_rows removeAllObjects];
    for (NSString *symbol in _symbols) {
        _rows[symbol] = [self makeRow:symbol];
        [self renderRow:symbol];
    }
    if (!_symbols.count) {
        NSTextField *empty = Label(13, NSFontWeightMedium, 0x95A7BF);
        empty.stringValue = @"点击 ＋ 添加股票、指数或期货代码";
        Place(empty, document, NSMakeRect(12, 25, 310, 18));
    }
    [self layOutRowsInDocument];
    [_scroll.contentView scrollToPoint:NSMakePoint(0, MAX(0, documentHeight - NSHeight(_scroll.contentView.bounds)))];
    [_scroll reflectScrolledClipView:_scroll.contentView];
    [self renderStatus];
}

- (void)layOutRowsInDocument {
    if (!_symbols.count) {
        return;
    }
    NSView *document = _scroll.documentView;
    NSMutableArray<NSView *> *views = [NSMutableArray arrayWithCapacity:_symbols.count + 1];
    for (NSUInteger index = 0; index < _symbols.count; index++) {
        DesktopMarketRow *row = _rows[_symbols[index]];
        CGFloat y = NSHeight(document.bounds) - (index + 1) * RowHeight;
        row.frame = NSMakeRect(0, y + 3, Width - 24, RowHeight - 6);
        [views addObject:row];
    }
    [views addObject:_dropLine];
    document.subviews = views;
}

- (NSUInteger)dropIndexAtPoint:(NSPoint)point {
    NSClipView *clip = _scroll.contentView;
    if (!NSPointInRect([clip convertPoint:point fromView:nil], clip.bounds) || !_symbols.count) {
        return NSNotFound;
    }
    NSView *document = _scroll.documentView;
    CGFloat y = [document convertPoint:point fromView:nil].y;
    CGFloat index = floor((NSMaxY(document.bounds) - y) / RowHeight);
    return (NSUInteger)fmax(0, fmin(index, _symbols.count - 1));
}

- (void)rowButton:(DesktopMarketRowButton *)button draggedToPoint:(NSPoint)point {
    if (button != _rows[button.identifier].button) {
        return;
    }
    NSClipView *clip = _scroll.contentView;
    NSPoint local = [clip convertPoint:point fromView:nil];
    NSRect bounds = clip.bounds;
    if (_scroll.hasVerticalScroller && NSPointInRect(local, bounds)) {
        CGFloat delta = 0;
        if (local.y > NSMaxY(bounds) - 18) {
            delta = 8;
        } else if (local.y < NSMinY(bounds) + 18) {
            delta = -8;
        }
        if (delta) {
            [clip scrollToPoint:NSMakePoint(NSMinX(bounds), NSMinY(bounds) + delta)];
            [_scroll reflectScrolledClipView:clip];
        }
    }
    NSUInteger source = [_symbols indexOfObject:button.identifier];
    NSUInteger target = [self dropIndexAtPoint:point];
    _dropLine.hidden = source == target || target == NSNotFound;
    if (!_dropLine.hidden) {
        NSRect row = _rows[_symbols[target]].frame;
        CGFloat y = source < target ? NSMinY(row) - 2 : NSMaxY(row) + 1;
        _dropLine.frame = NSMakeRect(8, y, Width - 40, 2);
    }
}

- (void)rowButton:(DesktopMarketRowButton *)button finishedAtPoint:(NSPoint)point commit:(BOOL)commit {
    _dropLine.hidden = YES;
    if (!commit || button != _rows[button.identifier].button) {
        return;
    }
    NSString *symbol = button.identifier;
    NSUInteger source = [_symbols indexOfObject:symbol];
    NSUInteger target = [self dropIndexAtPoint:point];
    if (source == NSNotFound || target == NSNotFound || source == target) {
        return;
    }
    [_symbols removeObjectAtIndex:source];
    [_symbols insertObject:symbol atIndex:target];
    [self saveSymbols];
    [self layOutRowsInDocument];
}

- (DesktopMarketRow *)makeRow:(NSString *)symbol {
    DesktopMarketRow *row = [[DesktopMarketRow alloc] initWithFrame:NSZeroRect];
    row.wantsLayer = YES;
    row.layer.backgroundColor = DesktopColor(0x172335).CGColor;
    row.layer.cornerRadius = 10;

    row.nameLabel = Label(14, NSFontWeightSemibold, 0xE6EEF9);
    row.metaLabel = Label(9, NSFontWeightMedium, 0x9FB2CD);
    row.priceLabel = Label(17, NSFontWeightSemibold, 0xF2F6FC);
    row.priceLabel.font = [NSFont monospacedDigitSystemFontOfSize:17 weight:NSFontWeightSemibold];
    row.changeLabel = Label(11, NSFontWeightMedium, 0x9DACC1);
    row.changeLabel.font = [NSFont monospacedDigitSystemFontOfSize:11 weight:NSFontWeightMedium];
    row.priceLabel.alignment = NSTextAlignmentRight;
    row.changeLabel.alignment = NSTextAlignmentRight;
    NSTextField *grip = Label(10, NSFontWeightSemibold, 0x778CA9);
    grip.stringValue = @"⠿";
    [grip setAccessibilityElement:NO];
    Place(grip, row, NSMakeRect(8, 23, 13, 14));
    Place(row.nameLabel, row, NSMakeRect(22, 30, 134, 21));
    Place(row.metaLabel, row, NSMakeRect(22, 11, 132, 14));
    Place(row.priceLabel, row, NSMakeRect(217, 29, 117, 23));
    Place(row.changeLabel, row, NSMakeRect(212, 10, 122, 16));
    row.chart = [[DesktopMarketChart alloc] initWithFrame:NSMakeRect(154, 11, 59, 38)];
    row.chart.miniature = YES;
    [row.chart setAccessibilityElement:NO];
    [row addSubview:row.chart];

    row.button = [[DesktopMarketRowButton alloc] initWithFrame:NSZeroRect];
    row.button.title = @"";
    row.button.target = self;
    row.button.action = @selector(openRow:);
    row.button.dragDelegate = self;
    row.button.bordered = NO;
    row.button.transparent = YES;
    row.button.identifier = symbol;
    row.button.toolTip = @"点击查看 K 线和行情详情，拖动可排序";
    Place(row.button, row, NSMakeRect(0, 0, Width - 24, RowHeight - 6));

    NSMenu *menu = [NSMenu new];
    NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"移除自选" action:@selector(removeSymbol:) keyEquivalent:@""];
    remove.target = self;
    remove.representedObject = symbol;
    [menu addItem:remove];
    row.menu = menu;
    row.button.menu = menu;
    return row;
}

- (void)renderRow:(NSString *)symbol {
    DesktopMarketRow *row = _rows[symbol];
    if (!row) {
        return;
    }
    DesktopQuote *quote = _quotes[symbol];
    row.nameLabel.stringValue = quote.name ?: [DesktopMarketService displayNameForSymbol:symbol];
    BOOL failed = [_failed containsObject:symbol];
    NSString *time = TimeLabel(quote.time, @"MM-dd HH:mm:ss");
    NSString *timestamp = quote.delayMinutes
        ? [NSString stringWithFormat:@"%@ · 延%ld分 · %@", symbol, (long)quote.delayMinutes, TimeLabel(quote.time, @"HH:mm:ss")]
        : [NSString stringWithFormat:@"%@  %@", symbol, time];
    row.metaLabel.stringValue = failed
        ? (quote ? [@"旧报价 · " stringByAppendingString:time] : @"行情暂不可用")
        : (quote ? timestamp : [symbol stringByAppendingString:@"  加载中"]);
    row.priceLabel.stringValue = quote ? Price(quote.price, quote.precision) : @"—";
    row.changeLabel.stringValue = Delta(quote);
    row.changeLabel.textColor = Trend(quote);
    NSArray *candles = _intraday[symbol] ?: @[];
    NSUInteger visibleCandles = MIN(22, candles.count);
    row.chart.candles = [candles subarrayWithRange:NSMakeRange(candles.count - visibleCandles, visibleCandles)];
    [row.button setAccessibilityLabel:[NSString stringWithFormat:@"%@，%@，%@。查看详情",
                                       row.nameLabel.stringValue, row.priceLabel.stringValue, row.changeLabel.stringValue]];
}

- (void)renderStatus {
    if (_manualRefreshPending && _requests.count) {
        _status.stringValue = @"正在刷新行情…";
        return;
    }
    if (_manualRefreshPending) {
        _manualRefreshPending = NO;
        _lastManualRefresh = NSDate.date;
    }
    if (_failed.count) {
        _status.stringValue = @"1 分钟 K 线 · 部分报价暂不可用，正在重试";
    } else if (_lastManualRefresh) {
        _status.stringValue = [NSString stringWithFormat:@"1 分钟 K 线 · 5 秒检查 · 手动刷新 %@",
                               TimeLabel(_lastManualRefresh, @"HH:mm:ss")];
    } else {
        _status.stringValue = @"1 分钟 K 线 · 每 5 秒检查报价";
    }
}

- (void)togglePin:(id)sender {
    (void)sender;
    BOOL pinned = [NSUserDefaults.standardUserDefaults boolForKey:PinnedKey];
    [NSUserDefaults.standardUserDefaults setBool:!pinned forKey:PinnedKey];
    [self switchPanelPinned:!pinned];
}

- (void)switchPanelPinned:(BOOL)pinned {
    if (pinned && !_floatingPanel) {
        _floatingPanel = [self makePanelPinned:YES];
        _floatingPanel.delegate = self;
    }

    // Keep the home window and its space association when the cross-space window takes over.
    NSPanel *incoming = pinned ? _floatingPanel : _homePanel;
    if (_panel != incoming) {
        BOOL visible = _panel.isVisible;
        [_panel orderOut:nil];
        _panel.contentView = [[NSView alloc] initWithFrame:_panelContent.frame];
        _panel = incoming;
        _panel.contentView = _panelContent;
        [self resizePanelForRows];
        if (visible) {
            [_panel orderFrontRegardless];
        }
    }
    _pin.title = pinned ? @"已置顶" : @"置顶";
}

- (void)showOptions:(id)sender {
    (void)sender;
    NSMenu *menu = [NSMenu new];
    if (_symbols.count) {
        NSMenuItem *remove = [[NSMenuItem alloc] initWithTitle:@"移除自选" action:nil keyEquivalent:@""];
        remove.submenu = [NSMenu new];
        for (NSString *symbol in _symbols) {
            NSString *name = _quotes[symbol].name ?: [DesktopMarketService displayNameForSymbol:symbol];
            NSMenuItem *choice = [[NSMenuItem alloc] initWithTitle:name action:@selector(removeSymbol:) keyEquivalent:@""];
            choice.target = self;
            choice.representedObject = symbol;
            [remove.submenu addItem:choice];
        }
        [menu addItem:remove];
    }
    if (menu.numberOfItems) {
        [menu addItem:NSMenuItem.separatorItem];
    }
    NSMenuItem *hide = [[NSMenuItem alloc] initWithTitle:@"隐藏行情窗" action:@selector(hidePanel:) keyEquivalent:@""];
    hide.target = self;
    [menu addItem:hide];
    [menu popUpMenuPositioningItem:nil atLocation:NSMakePoint(NSMinX(_menuButton.frame), NSMinY(_menuButton.frame) - 4)
                            inView:_panelContent];
}

- (void)hidePanel:(id)sender {
    (void)sender;
    [_panel close];
}

- (void)refreshAction:(id)sender {
    (void)sender;
    _manualRefreshPending = YES;
    [self refresh];
    [self renderStatus];
}

- (void)addSymbol:(id)sender {
    (void)sender;
    [NSApp activateIgnoringOtherApps:YES];
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"添加自选";
    alert.informativeText = @"输入行情代码，例如 AAPL、600519、上证指数、浙商黄金或 NQ-CFD。";
    [alert addButtonWithTitle:@"添加"];
    [alert addButtonWithTitle:@"取消"];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 275, 25)];
    field.placeholderString = @"行情代码";
    alert.accessoryView = field;
    alert.window.initialFirstResponder = field;
    [alert beginSheetModalForWindow:_panel completionHandler:^(NSModalResponse response) {
        if (response != NSAlertFirstButtonReturn) {
            return;
        }
        NSString *symbol = [DesktopMarketService normalizedSymbol:field.stringValue];
        if (!symbol) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showNotice:@"代码格式有误" detail:@"可以输入 AAPL、0700.HK 或 600519。"];
            });
        } else if ([self->_symbols containsObject:symbol] || [self->_adding containsObject:symbol]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showNotice:@"已在自选中或正在添加" detail:symbol];
            });
        } else {
            [self validateSymbol:symbol];
        }
    }];
}

- (void)showNotice:(NSString *)title detail:(NSString *)detail {
    if (!_panel.isVisible || _panel.attachedSheet) {
        return;
    }
    NSAlert *alert = [NSAlert new];
    alert.messageText = title;
    alert.informativeText = detail;
    [alert beginSheetModalForWindow:_panel completionHandler:nil];
}

- (void)validateSymbol:(NSString *)symbol {
    [_adding addObject:symbol];
    _status.stringValue = [NSString stringWithFormat:@"正在验证 %@…", symbol];
    __weak DesktopMarketController *weakSelf = self;
    [_service fetchQuote:symbol completion:^(DesktopQuote *quote, NSArray<DesktopCandle *> *candles) {
        DesktopMarketController *owner = weakSelf;
        if (!owner) {
            return;
        }
        [owner->_adding removeObject:symbol];
        [owner renderStatus];
        if (!quote) {
            [owner showNotice:@"未取得报价" detail:@"请检查行情代码，或稍后重试。"];
            return;
        }
        [owner->_symbols addObject:symbol];
        [owner saveSymbols];
        [owner storeQuote:quote candles:candles];
        [owner rebuildRows];
        [owner refresh];
    }];
}

- (void)removeSymbol:(NSMenuItem *)item {
    NSString *symbol = item.representedObject;
    if (![_symbols containsObject:symbol]) {
        return;
    }
    if ([_detailSymbol isEqualToString:symbol]) {
        [_detail close];
    }
    [_symbols removeObject:symbol];
    [_requests removeObjectForKey:symbol];
    [_quotes removeObjectForKey:symbol];
    [_intraday removeObjectForKey:symbol];
    [_failed removeObject:symbol];
    [_lastQuoteAttempts removeObjectForKey:symbol];
    [_lastHistoryAttempts removeObjectForKey:symbol];
    [_historyRequests removeObjectForKey:symbol];
    [_minuteHistoryFailures removeObject:symbol];
    [self saveSymbols];
    [self rebuildRows];
}

- (void)saveSymbols {
    [NSUserDefaults.standardUserDefaults setObject:[_symbols copy] forKey:SymbolsKey];
}

- (void)storeQuote:(DesktopQuote *)quote candles:(NSArray<DesktopCandle *> *)candles {
    NSString *symbol = quote.symbol;
    if (_quotes[symbol] && [quote.time compare:_quotes[symbol].time] == NSOrderedAscending) {
        return;
    }
    _quotes[symbol] = quote;
    [self mergeHistory:candles forSymbol:symbol];
}

- (void)mergeHistory:(NSArray<DesktopCandle *> *)candles forSymbol:(NSString *)symbol {
    NSArray<DesktopCandle *> *merged = DesktopMergeMinuteCandles(_intraday[symbol] ?: @[], candles, _quotes[symbol]);
    NSUInteger first = merged.count > 300 ? merged.count - 300 : 0;
    _intraday[symbol] = [merged subarrayWithRange:NSMakeRange(first, merged.count - first)];
}

- (void)refresh {
    [self refreshQuotesForcing:YES];
}

- (void)refreshQuotesForcing:(BOOL)force {
    if (!_panel.isVisible && !_detail.isVisible) {
        return;
    }
    NSArray<NSString *> *targets = _panel.isVisible ? [_symbols copy] : (_detailSymbol ? @[_detailSymbol] : @[]);
    NSDate *now = NSDate.date;
    for (NSString *symbol in targets) {
        NSDate *last = _lastQuoteAttempts[symbol];
        if (!_requests[symbol] && (force || !last || [now timeIntervalSinceDate:last] >=
                TimerInterval - 0.40)) {
            _lastQuoteAttempts[symbol] = now;
            [self requestQuote:symbol];
        }
        NSDate *historyAttempt = _lastHistoryAttempts[symbol];
        if ([DesktopMarketService hasSeparateMinuteHistory:symbol] && !_historyRequests[symbol] &&
            (!historyAttempt || (force && _manualRefreshPending) ||
             [now timeIntervalSinceDate:historyAttempt] >= MinuteHistoryInterval - 0.40)) {
            _lastHistoryAttempts[symbol] = now;
            [self requestMinuteHistory:symbol];
        }
    }
    if (_detail.isVisible) {
        [self requestVisibleChart];
    }
}

- (void)requestQuote:(NSString *)symbol {
    NSUUID *request = [NSUUID UUID];
    _requests[symbol] = request;
    __weak DesktopMarketController *weakSelf = self;
    [_service fetchQuote:symbol completion:^(DesktopQuote *quote, NSArray<DesktopCandle *> *candles) {
        DesktopMarketController *owner = weakSelf;
        if (!owner || ![owner->_requests[symbol] isEqual:request]) {
            return;
        }
        [owner->_requests removeObjectForKey:symbol];
        if (quote) {
            [owner->_failed removeObject:symbol];
            [owner storeQuote:quote candles:candles];
        } else {
            [owner->_failed addObject:symbol];
        }
        [owner renderRow:symbol];
        [owner renderStatus];
        if ([owner->_detailSymbol isEqualToString:symbol]) {
            [owner renderDetail];
        }
    }];
}

- (void)requestMinuteHistory:(NSString *)symbol {
    NSUUID *request = [NSUUID UUID];
    _historyRequests[symbol] = request;
    __weak DesktopMarketController *weakSelf = self;
    [_service fetchCandles:symbol daily:NO extended:NO completion:^(NSArray<DesktopCandle *> *candles) {
        DesktopMarketController *owner = weakSelf;
        if (!owner || ![owner->_historyRequests[symbol] isEqual:request]) {
            return;
        }
        [owner->_historyRequests removeObjectForKey:symbol];
        if (candles.count) {
            [owner->_minuteHistoryFailures removeObject:symbol];
            [owner mergeHistory:candles forSymbol:symbol];
        } else {
            [owner->_minuteHistoryFailures addObject:symbol];
        }
        [owner renderRow:symbol];
        if ([owner->_detailSymbol isEqualToString:symbol]) {
            [owner renderDetail];
        }
    }];
}

- (void)openRow:(NSButton *)button {
    NSString *symbol = button.identifier;
    if (![_symbols containsObject:symbol]) {
        return;
    }
    if (!_detail) {
        [self buildDetail];
    }
    if (![_detailSymbol isEqualToString:symbol]) {
        _detailSymbol = [symbol copy];
        _detailGeneration++;
        _detailMinuteHistory = nil;
        _detailMinuteCheckedAt = nil;
        _detailMinuteLoading = NO;
        _detailMinuteFailed = NO;
        [_chart resetViewport];
        _dailyCandles = nil;
        _dailyCheckedAt = nil;
        _chartFailed = NO;
        _range.selectedSegment = 0;
    }
    [self renderDetail];
    [NSApp activateIgnoringOtherApps:YES];
    [_detail makeKeyAndOrderFront:nil];
    [self updateTimer];
    [self refresh];
}

- (void)buildDetail {
    _detail = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 720, 485)
                                         styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                   NSWindowStyleMaskResizable
                                           backing:NSBackingStoreBuffered defer:NO];
    _detail.releasedWhenClosed = NO;
    _detail.delegate = self;
    _detail.contentMinSize = NSMakeSize(540, 365);
    _detail.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
    _detail.backgroundColor = DesktopColor(0x0D1420);
    _detail.tabbingMode = NSWindowTabbingModeDisallowed;
    [_detail center];
    [_detail setFrameAutosaveName:@"DesktopMarketDetail"];
    NSView *root = _detail.contentView;
    CGFloat width = NSWidth(root.bounds), height = NSHeight(root.bounds);

    _detailPrice = Label(25, NSFontWeightBold, 0xF0F5FC);
    _detailPrice.font = [NSFont monospacedDigitSystemFontOfSize:25 weight:NSFontWeightBold];
    Place(_detailPrice, root, NSMakeRect(19, height - 53, width - 38, 35));
    _detailPrice.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;
    _detailMeta = Label(11, NSFontWeightMedium, 0x9FB2CD);
    Place(_detailMeta, root, NSMakeRect(20, height - 75, width - 40, 18));
    _detailMeta.autoresizingMask = NSViewMinYMargin | NSViewWidthSizable;

    _range = [NSSegmentedControl segmentedControlWithLabels:@[@"1 分钟", @"日线"]
                                              trackingMode:NSSegmentSwitchTrackingSelectOne
                                                    target:self action:@selector(changeRange:)];
    _range.selectedSegment = 0;
    Place(_range, root, NSMakeRect(20, height - 112, 146, 26));
    _range.autoresizingMask = NSViewMinYMargin;
    NSButton *website = Button(@"来源网页", @"在浏览器打开行情来源", self, @selector(openSource:),
                               NSMakeRect(width - 108, height - 111, 88, 24));
    [root addSubview:website];
    website.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;
    NSButton *latest = Button(@"回到最新", @"回到最新 K 线", self, @selector(showLatestCandles:),
                              NSMakeRect(width - 190, height - 111, 74, 24));
    [root addSubview:latest];
    latest.autoresizingMask = NSViewMinXMargin | NSViewMinYMargin;

    _chart = [[DesktopMarketChart alloc] initWithFrame:NSMakeRect(20, 68, width - 40, height - 190)];
    _chart.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [root addSubview:_chart];
    _detailStats = Label(12, NSFontWeightMedium, 0xD4DFEE);
    Place(_detailStats, root, NSMakeRect(21, 39, width - 42, 19));
    _detailStats.autoresizingMask = NSViewWidthSizable;
    _detailStatus = Label(10, NSFontWeightMedium, 0x95A7BF);
    Place(_detailStatus, root, NSMakeRect(21, 16, width - 42, 16));
    _detailStatus.autoresizingMask = NSViewWidthSizable;
}

- (void)renderDetail {
    NSString *symbol = _detailSymbol;
    if (!symbol) {
        return;
    }
    DesktopQuote *quote = _quotes[symbol];
    NSString *name = quote.name ?: [DesktopMarketService displayNameForSymbol:symbol];
    BOOL daily = _range.selectedSegment == 1;
    BOOL failedQuote = [_failed containsObject:symbol];
    _detail.title = [NSString stringWithFormat:@"%@  ·  %@", name, symbol];
    if (quote) {
        NSString *price = [NSString stringWithFormat:@"%@ %@", Price(quote.price, quote.precision), quote.currency];
        NSMutableAttributedString *headline = [[NSMutableAttributedString alloc]
            initWithString:price attributes:@{NSForegroundColorAttributeName: DesktopColor(0xF0F5FC), NSFontAttributeName: _detailPrice.font}];
        [headline appendAttributedString:[[NSAttributedString alloc] initWithString:[@"    " stringByAppendingString:Delta(quote)]
            attributes:@{NSForegroundColorAttributeName: Trend(quote),
                         NSFontAttributeName: [NSFont monospacedDigitSystemFontOfSize:15 weight:NSFontWeightSemibold]}]];
        _detailPrice.attributedStringValue = headline;
        NSString *source = quote.delayMinutes
            ? [NSString stringWithFormat:@"%@ · 约延迟 %ld 分钟", quote.source, (long)quote.delayMinutes]
            : quote.source;
        _detailMeta.stringValue = [NSString stringWithFormat:@"%@  ·  %@%@",
                                   source, failedQuote ? @"旧报价 " : @"报价 ", TimeLabel(quote.time, @"MM-dd HH:mm:ss")];
        _detailStats.stringValue = [NSString stringWithFormat:@"昨收 %@     最高 %@     最低 %@",
                                    Price(quote.previousClose, quote.precision),
                                    Price(quote.dayHigh, quote.precision), Price(quote.dayLow, quote.precision)];
    } else {
        _detailPrice.stringValue = @"—";
        _detailMeta.stringValue = failedQuote ? @"报价暂不可用 · 稍后重试" : @"正在请求报价…";
        _detailStats.stringValue = @"";
    }
    NSArray<DesktopCandle *> *candles = daily ? _dailyCandles : _intraday[symbol];
    if (!daily && _detailMinuteHistory.count) {
        candles = DesktopMergeMinuteCandles(_detailMinuteHistory, candles ?: @[], nil);
    }
    _chart.daily = daily;
    _chart.precision = quote ? quote.precision : 2;
    _chart.candles = candles ?: @[];
    if (daily && _chartFailed) {
        _detailStatus.stringValue = candles.count ? @"日线更新失败 · 显示上次成功获取的数据" : @"日线暂不可用 · 稍后重试";
    } else if (!daily && _detailMinuteLoading && !_detailMinuteHistory.count) {
        _detailStatus.stringValue = @"正在加载更早的分钟 K 线…";
    } else if (!daily && (_detailMinuteFailed || [_minuteHistoryFailures containsObject:symbol]) && !_detailMinuteHistory.count) {
        _detailStatus.stringValue = @"历史分钟线暂不可用 · 稍后自动重试";
    } else if (!candles.count) {
        _detailStatus.stringValue = daily ? @"正在获取日线…" : @"正在获取 1 分钟 K 线…";
    } else {
        _detailStatus.stringValue = [NSString stringWithFormat:@"已加载 %lu 根 · 左右拖动看历史 · 滚轮缩放 · 悬停查看涨跌",
                                     (unsigned long)candles.count];
    }
}

- (void)showLatestCandles:(id)sender {
    (void)sender;
    [_chart showLatest];
}

- (void)changeRange:(id)sender {
    (void)sender;
    [_chart resetViewport];
    [self requestVisibleChart];
    [self renderDetail];
}

- (void)requestVisibleChart {
    if (_range.selectedSegment == 1) {
        [self requestDailyChart];
        return;
    }

    NSTimeInterval interval = _detailMinuteHistory.count ? 600 : 30;
    if (!_detailSymbol || _detailMinuteLoading ||
        (_detailMinuteCheckedAt && -_detailMinuteCheckedAt.timeIntervalSinceNow < interval)) {
        return;
    }
    _detailMinuteCheckedAt = NSDate.date;
    _detailMinuteLoading = YES;
    NSUInteger generation = _detailGeneration;
    __weak DesktopMarketController *weakSelf = self;
    [_service fetchCandles:_detailSymbol daily:NO extended:YES completion:^(NSArray<DesktopCandle *> *candles) {
        DesktopMarketController *owner = weakSelf;
        if (!owner || owner->_detailGeneration != generation) {
            return;
        }
        owner->_detailMinuteLoading = NO;
        owner->_detailMinuteFailed = candles.count == 0;
        if (candles.count) {
            owner->_detailMinuteHistory = candles;
        }
        [owner renderDetail];
    }];
}

- (void)requestDailyChart {
    if (!_detailSymbol || (_dailyCheckedAt && -_dailyCheckedAt.timeIntervalSinceNow < 60)) {
        return;
    }
    _dailyCheckedAt = NSDate.date;
    NSUInteger generation = _detailGeneration;
    __weak DesktopMarketController *weakSelf = self;
    [_service fetchCandles:_detailSymbol daily:YES extended:YES completion:^(NSArray<DesktopCandle *> *candles) {
        DesktopMarketController *owner = weakSelf;
        if (!owner || owner->_detailGeneration != generation) {
            return;
        }
        owner->_chartFailed = candles.count == 0;
        if (candles.count) {
            owner->_dailyCandles = candles;
        }
        [owner renderDetail];
    }];
}

- (void)openSource:(id)sender {
    (void)sender;
    if (_detailSymbol) {
        [NSWorkspace.sharedWorkspace openURL:[DesktopMarketService webURLForSymbol:_detailSymbol]];
    }
}

- (void)windowDidMove:(NSNotification *)notification {
    if (notification.object == _homePanel) {
        [self keepHomePanelOnPrimaryScreen];
    }
}

- (void)windowWillClose:(NSNotification *)notification {
    BOOL closingPanel = notification.object == _panel;
    if (closingPanel) {
        [_panel saveFrameUsingName:_panel == _homePanel ? PanelFrame : FloatingPanelFrame];
        [NSUserDefaults.standardUserDefaults setBool:NO forKey:VisibleKey];
    }
    if (notification.object == _detail) {
        _detailSymbol = nil;
        _detailGeneration++;
        _detailMinuteHistory = nil;
    }
    // The notification arrives before AppKit orders the closing window out.
    dispatch_async(dispatch_get_main_queue(), ^{ [self updateTimer]; });
}
@end
