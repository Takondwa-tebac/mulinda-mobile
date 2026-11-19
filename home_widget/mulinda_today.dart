// Schema for the "Lero / Today" home-screen widget.
//
// The native Android (Jetpack Glance) and iOS (WidgetKit) sources and the typed
// Dart helper are generated from this file. After editing it, run:
//
//   dart run home_widget_cli:home_widget generate --dart-out lib/features/home_widget/
//
// The app saves every label already translated (Chichewa or English, following
// the app language), so the native side only lays out strings. The generator
// has no progress primitive, so bars are five segments that switch on and off.
// The annotation must be a compile-time constant: no helper functions here.
import 'package:home_widget_generator/home_widget_generator.dart';

// Brand palette (lib/core/theme/app_colors.dart).
const _teal = HWColor.fixed(0xFF2EC4B6);
const _orange = HWColor.fixed(0xFFFF9F1C);
const _challengeLabel = HWColor.themed(
  light: HWColor.fixed(0xFFA35F00),
  dark: HWColor.fixed(0xFFFFBF69),
);
const _track = HWColor.themed(
  light: HWColor.fixed(0xFFE5E2E1),
  dark: HWColor.fixed(0xFF2A2E2C),
);
const _ink = HWColor.themed(
  light: HWColor.fixed(0xFF1C1B1B),
  dark: HWColor.fixed(0xFFE5E2E1),
);
const _muted = HWColor.themed(
  light: HWColor.fixed(0xFF3C4947),
  dark: HWColor.fixed(0xFFBBCAC6),
);
const _panel = HWColor.themed(
  light: HWColor.fixed(0xFFF0EDED),
  dark: HWColor.fixed(0xFF1E211F),
);
const _background = HWColor.themed(
  light: HWColor.fixed(0xFFFFFFFF),
  dark: HWColor.fixed(0xFF121413),
);

// Text styles.
const _titleStyle = HWTextStyle(fontSize: 15, color: _ink, fontWeight: HWFontWeight.bold);
const _bigStyle = HWTextStyle(fontSize: 24, color: _ink, fontWeight: HWFontWeight.bold);
const _bodyStyle = HWTextStyle(fontSize: 12, color: _muted);
const _rowStyle = HWTextStyle(fontSize: 12, color: _ink, fontWeight: HWFontWeight.w600);

// Bar segments: on (teal), on while over the allowance (orange), off (track).
const _segOn = HWDecoratedBox(
  decoration: HWBoxDecoration(color: _teal, borderRadius: HWBorderRadius.circular(3)),
  child: HWSizedBox(width: 20, height: 6),
);
const _segOver = HWDecoratedBox(
  decoration: HWBoxDecoration(color: _orange, borderRadius: HWBorderRadius.circular(3)),
  child: HWSizedBox(width: 20, height: 6),
);
const _segOff = HWDecoratedBox(
  decoration: HWBoxDecoration(color: _track, borderRadius: HWBorderRadius.circular(3)),
  child: HWSizedBox(width: 20, height: 6),
);
const _segFill = HWBoolConditional(
  data: HWBool('over', defaultValue: false),
  whenTrue: _segOver,
  whenFalse: _segOn,
);
const _bar = HWRow(
  spacing: 4,
  children: [
    HWBoolConditional(data: HWBool('bar1', defaultValue: false), whenTrue: _segFill, whenFalse: _segOff),
    HWBoolConditional(data: HWBool('bar2', defaultValue: false), whenTrue: _segFill, whenFalse: _segOff),
    HWBoolConditional(data: HWBool('bar3', defaultValue: false), whenTrue: _segFill, whenFalse: _segOff),
    HWBoolConditional(data: HWBool('bar4', defaultValue: false), whenTrue: _segFill, whenFalse: _segOff),
    HWBoolConditional(data: HWBool('bar5', defaultValue: false), whenTrue: _segFill, whenFalse: _segOff),
  ],
);

// Shared pieces.
const _header = HWRow(
  mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
  children: [
    HWText(HWString('title', defaultValue: 'Today'), style: _titleStyle),
    HWText(HWString('streak', defaultValue: ''), style: _titleStyle),
  ],
);
const _spent = HWText(HWString('spent', defaultValue: 'MK 0'), style: _bigStyle);
const _left = HWText(HWString('left', defaultValue: ''), style: _bodyStyle);

const _lastTxn = HWDecoratedBox(
  decoration: HWBoxDecoration(color: _panel, borderRadius: HWBorderRadius.circular(10)),
  child: HWPadding(
    padding: HWEdgeInsets.symmetric(horizontal: 8, vertical: 6),
    child: HWRow(
      mainAxisAlignment: HWMainAxisAlignment.spaceBetween,
      children: [
        HWText(HWString('lastTxn', defaultValue: ''), style: _rowStyle),
        HWText(HWString('lastAmount', defaultValue: ''), style: _rowStyle),
      ],
    ),
  ),
);

const _challenge = HWDecoratedBox(
  decoration: HWBoxDecoration(color: _panel, borderRadius: HWBorderRadius.circular(14)),
  child: HWPadding(
    padding: HWEdgeInsets.all(10),
    child: HWSizedBox(
      width: 112,
      child: HWColumn(
        crossAxisAlignment: HWCrossAxisAlignment.start,
        spacing: 4,
        children: [
          HWText(
            HWString('challengeLabel', defaultValue: ''),
            style: HWTextStyle(fontSize: 10, color: _challengeLabel, fontWeight: HWFontWeight.bold),
          ),
          HWText(HWString('challengeText', defaultValue: ''), style: _rowStyle),
          HWBoolConditional(
            data: HWBool('over', defaultValue: false),
            whenTrue: HWText(
              HWString('challengeStatus', defaultValue: ''),
              style: HWTextStyle(fontSize: 11, color: _orange, fontWeight: HWFontWeight.bold),
            ),
            whenFalse: HWText(
              HWString('challengeStatus', defaultValue: ''),
              style: HWTextStyle(fontSize: 11, color: _teal, fontWeight: HWFontWeight.bold),
            ),
          ),
        ],
      ),
    ),
  ),
);

// Shown before sign-in or before the first refresh.
const _empty = HWColumn(
  mainAxisAlignment: HWMainAxisAlignment.center,
  crossAxisAlignment: HWCrossAxisAlignment.start,
  spacing: 4,
  children: [
    HWText(HWString('title', defaultValue: 'Today'), style: _titleStyle),
    HWText(HWString('emptyText', defaultValue: 'Open Mulinda to see today'), style: _bodyStyle),
  ],
);

const _small = HWColumn(
  crossAxisAlignment: HWCrossAxisAlignment.start,
  spacing: 6,
  children: [_header, _spent, _bar, _left],
);

// The left column takes whatever width the challenge panel leaves. Five rows
// fit the ~110dp a 4x2 widget has inside its padding.
const _medium = HWRow(
  crossAxisAlignment: HWCrossAxisAlignment.start,
  spacing: 10,
  children: [
    HWSizedBox(
      width: double.infinity,
      child: HWColumn(
        crossAxisAlignment: HWCrossAxisAlignment.start,
        spacing: 5,
        children: [_header, _spent, _bar, _left, _lastTxn],
      ),
    ),
    _challenge,
  ],
);

@HomeWidget(
  name: 'Mulinda Today',
  description: "Today's spending, daily allowance and challenge.",
  android: HomeWidgetAndroidConfiguration(
    minWidth: 110,
    minHeight: 110,
    targetCellWidth: 4,
    targetCellHeight: 2,
    resizeMode: HWAndroidResizeMode.horizontalAndVertical,
    updatePeriodMillis: 1800000,
    useGlanceTheme: false,
    backgroundColor: _background,
  ),
  iOS: HomeWidgetIOSConfiguration(
    groupId: 'group.tech.lyncsystems.mulinda',
    supportedFamilies: [HWWidgetFamily.systemSmall, HWWidgetFamily.systemMedium],
    backgroundColor: _background,
  ),
  widget: HWBoolConditional(
    data: HWBool('hasData', defaultValue: false),
    whenFalse: _empty,
    whenTrue: HWSizeAdaptive(small: _small, medium: _medium),
  ),
)
class MulindaToday {}
