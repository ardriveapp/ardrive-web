import 'implementations/html_web.dart'
    if (dart.library.io) 'implementations/html_stub.dart' as implementation;

bool isTabHidden() => implementation.isTabHidden();

void whenTabIsUnhidden(Function onShow) =>
    implementation.whenTabIsUnhidden(onShow);
