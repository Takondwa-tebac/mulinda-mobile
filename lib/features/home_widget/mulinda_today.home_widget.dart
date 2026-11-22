// dart format off
// GENERATED CODE - DO NOT MODIFY BY HAND
// ignore_for_file: type=lint

import 'package:home_widget/home_widget.dart';

class MulindaTodayHomeWidget {
  const MulindaTodayHomeWidget._();

  static const String _$appGroupId = 'group.tech.lyncsystems.mulinda';

  static const String _$paramPrefix = 'home_widget.MulindaToday';

  static Future<void> saveData({
    bool? hasData,
    String? title,
    String? streak,
    String? spent,
    bool? bar1,
    bool? over,
    bool? bar2,
    bool? bar3,
    bool? bar4,
    bool? bar5,
    String? left,
    String? lastTxn,
    String? lastAmount,
    String? challengeLabel,
    String? challengeText,
    String? challengeStatus,
    String? emptyText,
  }) {
    return Future.wait([
      if (hasData != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.hasData', hasData, appGroupId: _$appGroupId),
      if (title != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.title', title, appGroupId: _$appGroupId),
      if (streak != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.streak', streak, appGroupId: _$appGroupId),
      if (spent != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.spent', spent, appGroupId: _$appGroupId),
      if (bar1 != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.bar1', bar1, appGroupId: _$appGroupId),
      if (over != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.over', over, appGroupId: _$appGroupId),
      if (bar2 != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.bar2', bar2, appGroupId: _$appGroupId),
      if (bar3 != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.bar3', bar3, appGroupId: _$appGroupId),
      if (bar4 != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.bar4', bar4, appGroupId: _$appGroupId),
      if (bar5 != null) HomeWidget.saveWidgetData<bool>('${_$paramPrefix}.bar5', bar5, appGroupId: _$appGroupId),
      if (left != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.left', left, appGroupId: _$appGroupId),
      if (lastTxn != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.lastTxn', lastTxn, appGroupId: _$appGroupId),
      if (lastAmount != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.lastAmount', lastAmount, appGroupId: _$appGroupId),
      if (challengeLabel != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.challengeLabel', challengeLabel, appGroupId: _$appGroupId),
      if (challengeText != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.challengeText', challengeText, appGroupId: _$appGroupId),
      if (challengeStatus != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.challengeStatus', challengeStatus, appGroupId: _$appGroupId),
      if (emptyText != null) HomeWidget.saveWidgetData<String>('${_$paramPrefix}.emptyText', emptyText, appGroupId: _$appGroupId),
    ]);
  }

  static Future<void> deleteData({
    bool hasData = false,
    bool title = false,
    bool streak = false,
    bool spent = false,
    bool bar1 = false,
    bool over = false,
    bool bar2 = false,
    bool bar3 = false,
    bool bar4 = false,
    bool bar5 = false,
    bool left = false,
    bool lastTxn = false,
    bool lastAmount = false,
    bool challengeLabel = false,
    bool challengeText = false,
    bool challengeStatus = false,
    bool emptyText = false,
  }) {
    return Future.wait([
      if (hasData) HomeWidget.saveWidgetData('${_$paramPrefix}.hasData', null, appGroupId: _$appGroupId),
      if (title) HomeWidget.saveWidgetData('${_$paramPrefix}.title', null, appGroupId: _$appGroupId),
      if (streak) HomeWidget.saveWidgetData('${_$paramPrefix}.streak', null, appGroupId: _$appGroupId),
      if (spent) HomeWidget.saveWidgetData('${_$paramPrefix}.spent', null, appGroupId: _$appGroupId),
      if (bar1) HomeWidget.saveWidgetData('${_$paramPrefix}.bar1', null, appGroupId: _$appGroupId),
      if (over) HomeWidget.saveWidgetData('${_$paramPrefix}.over', null, appGroupId: _$appGroupId),
      if (bar2) HomeWidget.saveWidgetData('${_$paramPrefix}.bar2', null, appGroupId: _$appGroupId),
      if (bar3) HomeWidget.saveWidgetData('${_$paramPrefix}.bar3', null, appGroupId: _$appGroupId),
      if (bar4) HomeWidget.saveWidgetData('${_$paramPrefix}.bar4', null, appGroupId: _$appGroupId),
      if (bar5) HomeWidget.saveWidgetData('${_$paramPrefix}.bar5', null, appGroupId: _$appGroupId),
      if (left) HomeWidget.saveWidgetData('${_$paramPrefix}.left', null, appGroupId: _$appGroupId),
      if (lastTxn) HomeWidget.saveWidgetData('${_$paramPrefix}.lastTxn', null, appGroupId: _$appGroupId),
      if (lastAmount) HomeWidget.saveWidgetData('${_$paramPrefix}.lastAmount', null, appGroupId: _$appGroupId),
      if (challengeLabel) HomeWidget.saveWidgetData('${_$paramPrefix}.challengeLabel', null, appGroupId: _$appGroupId),
      if (challengeText) HomeWidget.saveWidgetData('${_$paramPrefix}.challengeText', null, appGroupId: _$appGroupId),
      if (challengeStatus) HomeWidget.saveWidgetData('${_$paramPrefix}.challengeStatus', null, appGroupId: _$appGroupId),
      if (emptyText) HomeWidget.saveWidgetData('${_$paramPrefix}.emptyText', null, appGroupId: _$appGroupId),
    ]);
  }

  static Future<({bool? hasData, String? title, String? streak, String? spent, bool? bar1, bool? over, bool? bar2, bool? bar3, bool? bar4, bool? bar5, String? left, String? lastTxn, String? lastAmount, String? challengeLabel, String? challengeText, String? challengeStatus, String? emptyText})> getData() async {
    return (
      hasData: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.hasData', defaultValue: false, appGroupId: _$appGroupId),
      title: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.title', defaultValue: 'Today', appGroupId: _$appGroupId),
      streak: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.streak', defaultValue: '', appGroupId: _$appGroupId),
      spent: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.spent', defaultValue: 'MK 0', appGroupId: _$appGroupId),
      bar1: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.bar1', defaultValue: false, appGroupId: _$appGroupId),
      over: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.over', defaultValue: false, appGroupId: _$appGroupId),
      bar2: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.bar2', defaultValue: false, appGroupId: _$appGroupId),
      bar3: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.bar3', defaultValue: false, appGroupId: _$appGroupId),
      bar4: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.bar4', defaultValue: false, appGroupId: _$appGroupId),
      bar5: await HomeWidget.getWidgetData<bool>('${_$paramPrefix}.bar5', defaultValue: false, appGroupId: _$appGroupId),
      left: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.left', defaultValue: '', appGroupId: _$appGroupId),
      lastTxn: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.lastTxn', defaultValue: '', appGroupId: _$appGroupId),
      lastAmount: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.lastAmount', defaultValue: '', appGroupId: _$appGroupId),
      challengeLabel: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.challengeLabel', defaultValue: '', appGroupId: _$appGroupId),
      challengeText: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.challengeText', defaultValue: '', appGroupId: _$appGroupId),
      challengeStatus: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.challengeStatus', defaultValue: '', appGroupId: _$appGroupId),
      emptyText: await HomeWidget.getWidgetData<String>('${_$paramPrefix}.emptyText', defaultValue: 'Open Mulinda to see today', appGroupId: _$appGroupId),
    );
  }


  static Future<bool?> updateWidget() {
    return HomeWidget.updateWidget(
      androidName: 'MulindaTodayHomeWidgetReceiver',
      iOSName: 'MulindaTodayHomeWidget',
    );
  }

  /// Asks the launcher to re-render this widget's gallery preview.
  ///
  /// Android 15 and newer only; returns false elsewhere and when the system
  /// rate limit (about two updates per hour and widget) was hit. The plugin
  /// registers the preview automatically when the app starts, so this is only
  /// needed after data changes that should show in the gallery right away.
  static Future<bool> updatePreview() async {
    return await HomeWidget.updateWidgetPreview(
      androidName: 'MulindaTodayHomeWidgetReceiver',
    ) ?? false;
  }

  /// Whether the launcher lets the app ask to add this widget to the home
  /// screen: Android 8 or newer with a launcher that supports pinning. Always
  /// false on iOS.
  static Future<bool> isRequestPinWidgetSupported() async {
    return await HomeWidget.isRequestPinWidgetSupported() ?? false;
  }

  /// Asks the launcher to add this widget to the home screen.
  ///
  /// Shows the system pin dialog where [isRequestPinWidgetSupported] is true
  /// and does nothing anywhere else.
  static Future<void> requestPinWidget() {
    return HomeWidget.requestPinWidget(
      androidName: 'MulindaTodayHomeWidgetReceiver',
    );
  }

  /// Every instance of this widget currently placed on a home screen.
  ///
  /// Android reports one entry per placed instance, iOS one entry per family
  /// the widget is placed in.
  static Future<List<HomeWidgetInfo>> getInstalledWidgets() async {
    final widgets = await HomeWidget.getInstalledWidgets();
    return widgets.where(_$isThisWidget).toList();
  }

  /// Whether at least one instance of this widget is on a home screen.
  static Future<bool> isInstalled() async {
    return (await getInstalledWidgets()).isNotEmpty;
  }

  /// Whether [info] describes this widget.
  ///
  /// Android reports the provider's short class name — `.Receiver` when it
  /// lives in the package of the application id, and the qualified name
  /// otherwise — which is why the suffix is matched.
  static bool _$isThisWidget(HomeWidgetInfo info) {
    final androidClassName = info.androidClassName;
    if (androidClassName != null) {
      return androidClassName.endsWith('.MulindaTodayHomeWidgetReceiver');
    }
    return info.iOSKind == 'MulindaTodayHomeWidget';
  }
}
