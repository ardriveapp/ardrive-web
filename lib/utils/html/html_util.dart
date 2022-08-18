import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

bool isBrowserTabHidden() => implementation.isTabHidden();

void whenBrowserTabIsUnhidden(Function onShow) =>
    implementation.whenTabIsUnhidden(onShow);

void refreshHTMLPageAtInterval(Duration duration) =>
    implementation.refreshPageAtInterval(duration);

void onArConnectWalletSwitch(Function onWalletSwitch) =>
    implementation.onWalletSwitch(onWalletSwitch);

void triggerHTMLPageReload() => implementation.reload();
