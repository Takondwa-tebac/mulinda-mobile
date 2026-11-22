import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/analytics/analytics.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../referral/data/referral_repository.dart';
import '../data/story_format.dart';
import '../data/story_models.dart';
import 'story_motion.dart';
import 'story_player.dart';
import 'story_slide_parts.dart';
import 'story_slides.dart';

/// One figure on the share card.
class ShareTile {
  const ShareTile(this.value, this.label);

  final String value;
  final String label;
}

/// What the share card shows. Never a person's name and never the invite
/// link: only the period, the money style, shares or (when the person chose
/// to show them) amounts, and category names.
class ShareCardContent {
  const ShareCardContent({required this.heading, required this.bigHeading, this.styleTitle, required this.tiles, this.footer});

  final String heading;

  /// The year card shows the year big and orange; the month card a small label.
  final bool bigHeading;
  final String? styleTitle;
  final List<ShareTile> tiles;
  final String? footer;

  static ShareCardContent of(MoneyStory s, {required bool amounts}) {
    final style = s.moneyStyle?.titleKey.tr();
    final spent = s.spending;
    final income = s.income;
    final amountTiles = [
      if (amounts && spent != null) ShareTile(storyAmount(spent), 'stories.card.spent'.tr()),
      if (amounts && income != null) ShareTile(storyAmount(income), 'stories.card.cameIn'.tr()),
    ];

    if (s.kind == StoryKind.year) {
      final messages = s.messagesRecorded ?? 0;
      final biggest = monthOfKey(s.biggestMonth);
      final goals = s.goalsReached?.count ?? 0;
      return ShareCardContent(
        heading: '${s.period.year}',
        bigHeading: true,
        styleTitle: style,
        tiles: [
          if (messages > 0) ShareTile(groupCount(messages), 'stories.card.messages'.tr()),
          if (s.topCategories.isNotEmpty) ShareTile(s.topCategories.first.name, 'stories.card.topCategory'.tr()),
          if (biggest != null) ShareTile(monthName(biggest), 'stories.card.biggestMonth'.tr()),
          if (goals > 0) ShareTile('$goals', 'stories.card.goals'.tr()),
          ...amountTiles,
        ],
      );
    }

    final kept = s.keptRatio;
    final change = s.changeVsPrevious;
    final prev = monthOfKey(change?.previousKey) ?? ((s.period.month ?? 1) == 1 ? 12 : (s.period.month ?? 1) - 1);
    return ShareCardContent(
      heading: storyTitle(s),
      bigHeading: false,
      styleTitle: style,
      tiles: [
        if (kept != null)
          ShareTile(storyPercent(kept.abs()), (kept < 0 ? 'stories.card.overspent' : 'stories.card.kept').tr()),
        if (change != null)
          ShareTile(
            '${change.percent}%',
            (change.isLess
                    ? 'stories.card.lessThan'
                    : change.isMore
                    ? 'stories.card.moreThan'
                    : 'stories.card.sameAs')
                .tr(namedArgs: {'month': monthName(prev)}),
          ),
        ...amountTiles,
      ],
      footer: s.topCategories.isEmpty
          ? null
          : 'stories.card.top'.tr(namedArgs: {'names': s.topCategories.take(3).map((c) => c.name).join(' · ')}),
    );
  }
}

/// The share card as it looks on the last slide and in the picture.
class StoryShareCard extends StatelessWidget {
  const StoryShareCard({super.key, required this.content, this.scale = 1});

  final ShareCardContent content;

  /// Everything grows with this (the picture uses a larger card).
  final double scale;

  @override
  Widget build(BuildContext context) {
    double z(double v) => v * scale;
    final c = content;
    return Container(
      padding: EdgeInsets.all(z(20)),
      decoration: BoxDecoration(
        color: c.bigHeading ? AppColors.tealDeep : AppColors.onTeal,
        borderRadius: BorderRadius.circular(z(28)),
        border: Border.all(color: AppColors.tealPale.withValues(alpha: 0.25)),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.white, height: 1.2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.heading,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: c.bigHeading
                        ? TextStyle(fontSize: z(30), fontWeight: StoryType.heavy, color: AppColors.orange)
                        : TextStyle(fontSize: z(14), fontWeight: FontWeight.w700, color: AppColors.tealPale),
                  ),
                ),
                StoryLogo(size: z(22)),
                SizedBox(width: z(6)),
                Text('app.name'.tr(), style: TextStyle(fontSize: z(13), fontWeight: FontWeight.w700)),
              ],
            ),
            if (c.styleTitle != null) ...[
              SizedBox(height: z(12)),
              Text(
                c.styleTitle!,
                style: TextStyle(
                  fontSize: z(c.bigHeading ? 24 : 28),
                  fontWeight: StoryType.heavy,
                  height: 1.05,
                  color: c.bigHeading ? AppColors.white : AppColors.orange,
                ),
              ),
            ],
            if (c.tiles.isNotEmpty) ...[
              SizedBox(height: z(12)),
              LayoutBuilder(
                builder: (context, box) {
                  final gap = z(8);
                  final w = (box.maxWidth - gap) / 2;
                  return Wrap(
                    spacing: gap,
                    runSpacing: gap,
                    children: [
                      for (final t in c.tiles)
                        Container(
                          width: w,
                          padding: EdgeInsets.all(z(10)),
                          decoration: BoxDecoration(
                            color: AppColors.tealPale.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(z(12)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  t.value,
                                  maxLines: 1,
                                  style: TextStyle(fontSize: z(19), fontWeight: StoryType.heavy),
                                ),
                              ),
                              SizedBox(height: z(2)),
                              Text(
                                t.label,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: z(11), color: AppColors.tealPale),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
            if (c.footer != null) ...[
              SizedBox(height: z(12)),
              Text(c.footer!, style: TextStyle(fontSize: z(13), color: AppColors.tealPale)),
            ],
          ],
        ),
      ),
    );
  }
}

/// The saved and shared picture: 9:16, laid out at 360 x 640 and captured at
/// 3x, so 1080 x 1920 (WhatsApp status size).
class StoryShareImage extends StatelessWidget {
  const StoryShareImage({super.key, required this.content});

  static const logicalSize = Size(360, 640);
  static const pixelRatio = 3.0;

  final ShareCardContent content;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: logicalSize,
      child: ColoredBox(
        color: AppColors.tealDeep,
        child: Stack(
          children: [
            Positioned(
              right: -90,
              top: 70,
              child: _Circle(size: 260, color: AppColors.orange.withValues(alpha: 0.22)),
            ),
            Positioned(
              left: -70,
              bottom: 90,
              child: _Circle(size: 200, color: AppColors.teal.withValues(alpha: 0.25)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xxl, AppSpacing.xl, AppSpacing.xxl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const StoryLogo(size: 32),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        'app.name'.tr(),
                        style: const TextStyle(color: AppColors.white, fontSize: 18, fontWeight: StoryType.heavy),
                      ),
                    ],
                  ),
                  const Spacer(),
                  StoryShareCard(content: content, scale: 1.05),
                  const Spacer(),
                  Text(
                    'stories.card.tagline'.tr(),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: AppColors.tealPale, fontSize: 13, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Circle extends StatelessWidget {
  const _Circle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: DecoratedBox(decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
  );
}

enum _Busy { none, saving, sharing }

/// The last slide: the card, the Show amounts switch, Save and Share to
/// status, and for the year "Invite a friend to see their year".
class StoryShareSlide extends ConsumerStatefulWidget {
  const StoryShareSlide({
    super.key,
    required this.story,
    required this.amounts,
    required this.onAmountsChanged,
    this.onInvite,
  });

  final MoneyStory story;
  final bool amounts;
  final ValueChanged<bool> onAmountsChanged;

  /// Year story: open Invite friends.
  final VoidCallback? onInvite;

  @override
  ConsumerState<StoryShareSlide> createState() => _StoryShareSlideState();
}

class _StoryShareSlideState extends ConsumerState<StoryShareSlide> {
  final _imageKey = GlobalKey(debugLabel: 'story-share-image');
  _Busy _busy = _Busy.none;

  MoneyStory get _s => widget.story;

  Map<String, Object?> get _props => {'story': _s.kind.name, 'key': _s.period.key};

  String get _fileName => 'mulinda-${_s.kind.name}-${_s.period.key}';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // So the logo is already in the picture when it is saved or shared.
    precacheImage(StoryLogo.asset, context);
  }

  Future<Uint8List> _renderPng() async {
    // Let a just-toggled "Show amounts" reach the picture first.
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _imageKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: StoryShareImage.pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _snack(String key) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(key.tr())));
  }

  Future<void> _save() async {
    setState(() => _busy = _Busy.saving);
    try {
      final bytes = await _renderPng();
      // Android 11 and later need no permission to add a picture; older
      // versions ask once for storage.
      final allowed = await Gal.hasPermission(toAlbum: true) || await Gal.requestPermission(toAlbum: true);
      if (!allowed) {
        _snack('stories.share.saveDenied');
        return;
      }
      await Gal.putImageBytes(bytes, album: 'Mulinda', name: _fileName);
      unawaited(Analytics.track('story_saved', _props));
      _snack('stories.share.saved');
    } on GalException catch (e) {
      _snack(e.type == GalExceptionType.permissionDenied ? 'stories.share.saveDenied' : 'stories.share.saveFailed');
    } catch (_) {
      _snack('stories.share.saveFailed');
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  /// The share message: the story and, when it can be loaded, the invite link.
  Future<String> _message() async {
    String? link;
    try {
      final info = await ref.read(referralInfoProvider.future).timeout(const Duration(seconds: 6));
      link = info.link.isEmpty ? null : info.link;
    } catch (_) {
      link = null;
    }
    final m = _s.period.month;
    final period = m == null ? '${_s.period.year}' : '${monthName(m)} ${_s.period.year}';
    return link == null
        ? 'stories.share.messageNoLink'.tr(namedArgs: {'period': period})
        : 'stories.share.message'.tr(namedArgs: {'period': period, 'link': link});
  }

  Future<void> _share() async {
    setState(() => _busy = _Busy.sharing);
    try {
      final bytes = await _renderPng();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$_fileName.png');
      await file.writeAsBytes(bytes, flush: true);
      final text = await _message();
      if (!mounted) return;
      final result = await Share.shareXFiles([XFile(file.path, mimeType: 'image/png')], text: text);
      if (result.status == ShareResultStatus.success) {
        unawaited(Analytics.track('story_shared', _props));
        _snack('stories.share.shared');
      }
    } catch (_) {
      _snack('stories.share.shareFailed');
    } finally {
      if (mounted) setState(() => _busy = _Busy.none);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = ShareCardContent.of(_s, amounts: widget.amounts);
    final idle = _busy == _Busy.none;
    Widget spinner(Color color) =>
        SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The picture, laid out off screen at its full size.
        ExcludeSemantics(
          child: SizedBox.shrink(
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: StoryShareImage.logicalSize.width,
              maxWidth: StoryShareImage.logicalSize.width,
              minHeight: StoryShareImage.logicalSize.height,
              maxHeight: StoryShareImage.logicalSize.height,
              child: Transform.translate(
                offset: const Offset(-10000, 0),
                child: RepaintBoundary(key: _imageKey, child: StoryShareImage(content: content)),
              ),
            ),
          ),
        ),
        StoryReveal(child: StoryShareCard(content: content)),
        const SizedBox(height: AppSpacing.md),
        StoryReveal(
          delay: Reveal.a2,
          child: Center(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.white.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              padding: const EdgeInsets.only(left: AppSpacing.lg, right: AppSpacing.xs),
              child: MergeSemantics(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(
                        'stories.share.showAmounts'.tr(),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Switch(
                      key: const ValueKey('story-amounts'),
                      value: widget.amounts,
                      onChanged: widget.onAmountsChanged,
                      activeThumbColor: AppColors.onOrange,
                      activeTrackColor: AppColors.orange,
                      inactiveThumbColor: AppColors.tealPale,
                      inactiveTrackColor: AppColors.white.withValues(alpha: 0.15),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        StoryReveal(
          delay: Reveal.a3,
          child: Row(
            children: [
              Expanded(
                flex: 10,
                child: OutlinedButton(
                  key: const ValueKey('story-save'),
                  onPressed: idle ? _save : null,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.white,
                    disabledForegroundColor: AppColors.white.withValues(alpha: 0.6),
                    side: BorderSide(color: AppColors.white.withValues(alpha: 0.45)),
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                  child: _busy == _Busy.saving ? spinner(AppColors.white) : Text('stories.share.save'.tr()),
                ),
              ),
              const SizedBox(width: AppSpacing.md - 2),
              Expanded(
                flex: 14,
                child: FilledButton(
                  key: const ValueKey('story-share'),
                  onPressed: idle ? _share : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.orange,
                    foregroundColor: AppColors.onOrange,
                    disabledBackgroundColor: AppColors.orange.withValues(alpha: 0.6),
                    disabledForegroundColor: AppColors.onOrange,
                    minimumSize: const Size.fromHeight(52),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontSize: 15, fontWeight: StoryType.heavy),
                  ),
                  child: _busy == _Busy.sharing
                      ? spinner(AppColors.onOrange)
                      : Text('stories.share.share'.tr(), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        StoryReveal(
          delay: Reveal.a4,
          child: Text(
            'stories.share.note'.tr(),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: AppColors.tealPale, height: 1.4),
          ),
        ),
        if (widget.onInvite != null) ...[
          const SizedBox(height: AppSpacing.xs),
          StoryReveal(
            delay: Reveal.a4,
            child: Center(
              child: TextButton(
                key: const ValueKey('story-invite'),
                onPressed: widget.onInvite,
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.tealPale,
                  minimumSize: const Size(0, AppSpacing.minTouch),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.tealPale,
                  ),
                ),
                child: Text('stories.year.invite'.tr()),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
