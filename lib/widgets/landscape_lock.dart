import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Keeps the app in landscape while any screen using this is open, so going back
/// from one landscape screen to another doesn't briefly unlock rotation.
mixin LandscapeLock<T extends StatefulWidget> on State<T> {
  static var _openScreens = 0;

  @override
  void initState() {
    super.initState();
    if (_openScreens++ == 0) {
      SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    }
  }

  @override
  void dispose() {
    if (--_openScreens == 0) SystemChrome.setPreferredOrientations([]);
    super.dispose();
  }
}
