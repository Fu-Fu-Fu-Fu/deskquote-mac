#import <AppKit/AppKit.h>

@interface DesktopMarketController : NSObject
- (void)restoreIfVisible;
- (void)showPanel;
- (void)toggle;
- (void)refresh;
@end
