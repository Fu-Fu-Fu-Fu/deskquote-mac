#import <AppKit/AppKit.h>

#import "StockBarAppDelegate.h"

static NSMenu *BuildMainMenu(void) {
    NSMenu *menu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    appItem.submenu = [[NSMenu alloc] initWithTitle:@"StockBar"];
    [appItem.submenu addItemWithTitle:@"退出 StockBar" action:@selector(terminate:) keyEquivalent:@"q"];
    [menu addItem:appItem];

    NSMenuItem *editItem = [[NSMenuItem alloc] initWithTitle:@"编辑" action:nil keyEquivalent:@""];
    editItem.submenu = [[NSMenu alloc] initWithTitle:@"编辑"];
    [editItem.submenu addItemWithTitle:@"剪切" action:@selector(cut:) keyEquivalent:@"x"];
    [editItem.submenu addItemWithTitle:@"复制" action:@selector(copy:) keyEquivalent:@"c"];
    [editItem.submenu addItemWithTitle:@"粘贴" action:@selector(paste:) keyEquivalent:@"v"];
    [editItem.submenu addItemWithTitle:@"全选" action:@selector(selectAll:) keyEquivalent:@"a"];
    [menu addItem:editItem];
    return menu;
}

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        StockBarAppDelegate *delegate = [[StockBarAppDelegate alloc] init];
        application.delegate = delegate;
        application.mainMenu = BuildMainMenu();
        [application run];
    }
    return 0;
}
