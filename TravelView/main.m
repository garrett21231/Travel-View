#import <TargetConditionals.h>
#if TARGET_OS_OSX
#import <AppKit/AppKit.h>
#else
#import <UIKit/UIKit.h>
#endif
#import <WebKit/WebKit.h>
#include <Python.h>

// This points to app.py's render function for the lifetime of the app.
static PyObject *renderer;

#if TARGET_OS_IOS
static PyStatus appendSearchPath(PyConfig *config, NSString *path) {
    wchar_t *decoded = Py_DecodeLocale(path.fileSystemRepresentation, NULL);
    if (decoded == NULL) {
        return PyStatus_Error("Could not decode a Python library path");
    }
    PyStatus status = PyWideStringList_Append(&config->module_search_paths, decoded);
    PyMem_RawFree(decoded);
    return status;
}
#endif

static PyObject *loadRenderer(void) {
    PyPreConfig preconfig;
    PyPreConfig_InitIsolatedConfig(&preconfig);
    preconfig.utf8_mode = 1;
    PyStatus status = Py_PreInitialize(&preconfig);
    if (PyStatus_Exception(status)) {
        Py_ExitStatusException(status);
    }

    NSString *resources = NSBundle.mainBundle.resourcePath;
    PyConfig config;
    PyConfig_InitIsolatedConfig(&config);
    config.write_bytecode = 0;
    config.buffered_stdio = 0;
    // macOS uses Xcode's Python. iOS loads its Python library from the app bundle.
#if TARGET_OS_OSX
    status = PyConfig_SetBytesString(&config, &config.home, TRAVEL_VIEW_PYTHON_HOME);
#else
    NSString *home = [resources stringByAppendingPathComponent:@"python"];
    NSString *version = [NSString stringWithFormat:@"lib/python%d.%d", PY_MAJOR_VERSION, PY_MINOR_VERSION];
    NSString *stdlib = [home stringByAppendingPathComponent:version];
    config.install_signal_handlers = 1;
    config.module_search_paths_set = 1;
    status = PyConfig_SetBytesString(&config, &config.home, home.fileSystemRepresentation);
    if (!PyStatus_Exception(status)) {
        status = appendSearchPath(&config, stdlib);
    }
    if (!PyStatus_Exception(status)) {
        status = appendSearchPath(&config, [stdlib stringByAppendingPathComponent:@"lib-dynload"]);
    }
#endif
    if (!PyStatus_Exception(status)) {
        status = Py_InitializeFromConfig(&config);
    }
    PyConfig_Clear(&config);
    if (PyStatus_Exception(status)) {
        Py_ExitStatusException(status);
    }

    // Search the bundled resources so Python can import app.py and trips.py.
    PyObject *resourcePath = PyUnicode_DecodeFSDefault(resources.fileSystemRepresentation);
    if (resourcePath == NULL) {
        return NULL;
    }
    int result = PyList_Insert(PySys_GetObject("path"), 0, resourcePath);
    Py_DECREF(resourcePath);
    if (result < 0) {
        return NULL;
    }

    PyObject *module = PyImport_ImportModule("app");
    if (module == NULL) {
        return NULL;
    }
    PyObject *render = PyObject_GetAttrString(module, "render");
    Py_DECREF(module);
    return render;
}

@interface TravelViewContent : NSObject <WKScriptMessageHandler>
- (WKWebView *)makeWebView;
@end

@implementation TravelViewContent {
    __weak WKWebView *_webView;
}

- (void)showPageForJSON:(NSString *)json {
    // Python returns HTML, which replaces the current screen in WebKit.
    PyObject *result = PyObject_CallFunction(renderer, "s", json.UTF8String);
    const char *html = result == NULL ? NULL : PyUnicode_AsUTF8(result);
    if (html != NULL) {
        [_webView loadHTMLString:[NSString stringWithUTF8String:html] baseURL:nil];
    } else {
        PyErr_Print();
        [_webView loadHTMLString:@"<h1>Travel View</h1><p>Couldn’t open this screen. See the Xcode console.</p>" baseURL:nil];
    }
    Py_XDECREF(result);
}

- (WKWebView *)makeWebView {
    WKWebViewConfiguration *configuration = [WKWebViewConfiguration new];
    configuration.websiteDataStore = WKWebsiteDataStore.nonPersistentDataStore;
    [configuration.userContentController addScriptMessageHandler:self name:@"travelView"];
    WKWebView *webView = [[WKWebView alloc] initWithFrame:CGRectMake(0, 0, 0, 0) configuration:configuration];
    _webView = webView;
    [self showPageForJSON:@"{}"];
    return webView;
}

- (void)userContentController:(WKUserContentController *)controller didReceiveScriptMessage:(WKScriptMessage *)message {
    // Convert a WebKit button click or form submission to the JSON Python expects.
    if (message.frameInfo.isMainFrame && [message.body isKindOfClass:NSDictionary.class]) {
        NSData *data = [NSJSONSerialization dataWithJSONObject:message.body options:0 error:NULL];
        if (data != nil) {
            NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            [self showPageForJSON:json];
        }
    }
}
@end

#if TARGET_OS_OSX
@interface TravelViewDelegate : NSObject <NSApplicationDelegate>
@end

@implementation TravelViewDelegate {
    NSWindow *_window;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSRect size = NSMakeRect(0, 0, 800, 540);
    _window = [[NSWindow alloc] initWithContentRect:size
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                  NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    _window.title = @"Travel View";
    _window.contentMinSize = NSMakeSize(660, 460);
    _window.releasedWhenClosed = NO;
    _window.contentView = [[TravelViewContent new] makeWebView];
    [_window center];
    [_window makeKeyAndOrderFront:nil];
    [NSApp activate];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)application {
    return YES;
}

@end

static void setUpMenus(NSApplication *app) {
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *application = [mainMenu addItemWithTitle:@"Travel View" action:NULL keyEquivalent:@""];
    application.submenu = [[NSMenu alloc] initWithTitle:@"Travel View"];
    [application.submenu addItemWithTitle:@"Quit Travel View" action:@selector(terminate:) keyEquivalent:@"q"];

    NSMenuItem *edit = [mainMenu addItemWithTitle:@"Edit" action:NULL keyEquivalent:@""];
    edit.submenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [edit.submenu addItemWithTitle:@"Cut" action:@selector(cut:) keyEquivalent:@"x"];
    [edit.submenu addItemWithTitle:@"Copy" action:@selector(copy:) keyEquivalent:@"c"];
    [edit.submenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
    [edit.submenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    app.mainMenu = mainMenu;
}
#else
@interface TravelViewSceneDelegate : UIResponder <UIWindowSceneDelegate>
@property (nonatomic, strong) UIWindow *window;
@end

@implementation TravelViewSceneDelegate
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    UIViewController *viewController = [UIViewController new];
    viewController.view.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
        return traits.userInterfaceStyle == UIUserInterfaceStyleDark
            ? [UIColor colorWithRed:20/255.0 green:30/255.0 blue:43/255.0 alpha:1]
            : [UIColor colorWithRed:227/255.0 green:234/255.0 blue:246/255.0 alpha:1];
    }];

    WKWebView *webView = [[TravelViewContent new] makeWebView];
    webView.translatesAutoresizingMaskIntoConstraints = NO;
    webView.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    webView.scrollView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    [viewController.view addSubview:webView];
    // Keep the screen controls clear of the status bar and home indicator.
    UILayoutGuide *safeArea = viewController.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [webView.topAnchor constraintEqualToAnchor:safeArea.topAnchor],
        [webView.bottomAnchor constraintEqualToAnchor:safeArea.bottomAnchor],
        [webView.leadingAnchor constraintEqualToAnchor:safeArea.leadingAnchor],
        [webView.trailingAnchor constraintEqualToAnchor:safeArea.trailingAnchor],
    ]];

    self.window = [[UIWindow alloc] initWithWindowScene:(UIWindowScene *)scene];
    self.window.rootViewController = viewController;
    [self.window makeKeyAndVisible];
}
@end

@interface TravelViewDelegate : UIResponder <UIApplicationDelegate>
@end

@implementation TravelViewDelegate
- (UISceneConfiguration *)application:(UIApplication *)application
    configurationForConnectingSceneSession:(UISceneSession *)session
    options:(UISceneConnectionOptions *)options {
    UISceneConfiguration *configuration = [[UISceneConfiguration alloc] initWithName:nil sessionRole:session.role];
    configuration.delegateClass = TravelViewSceneDelegate.class;
    return configuration;
}
@end
#endif

int main(int argc, char *argv[]) {
    @autoreleasepool {
        renderer = loadRenderer();
        if (renderer == NULL) {
            PyErr_Print();
            Py_FinalizeEx();
            return EXIT_FAILURE;
        }
#if TARGET_OS_OSX
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        setUpMenus(app);
        __attribute__((objc_precise_lifetime)) TravelViewDelegate *delegate =
            [TravelViewDelegate new];
        app.delegate = delegate;
        [app run];
        Py_DECREF(renderer);
        return Py_FinalizeEx() == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
#else
        int result = UIApplicationMain(argc, argv, nil, NSStringFromClass(TravelViewDelegate.class));
        Py_DECREF(renderer);
        Py_FinalizeEx();
        return result;
#endif
    }
}
