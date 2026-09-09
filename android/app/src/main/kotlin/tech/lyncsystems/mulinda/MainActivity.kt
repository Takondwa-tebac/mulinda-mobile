package tech.lyncsystems.mulinda

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity (not FlutterActivity) is required by local_auth so
// the biometric prompt can attach to the activity's fragment manager.
class MainActivity : FlutterFragmentActivity()
