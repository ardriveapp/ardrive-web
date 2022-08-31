import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

bool isBrowserTabHidden() => implementation.isTabHidden();

void whenBrowserTabIsUnhidden(Function onShow) =>
    implementation.whenTabIsUnhidden(onShow);

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();

Future<void> closeVisibilityChangeStream() =>
    implementation.closeVisibilityChangeStream();
