import 'package:flutter/material.dart';

/// Logos of the companies listed on the Malawi Stock Exchange, bundled with the
/// app (assets/mse_logos), by ticker. A ticker not listed here, or a missing
/// file, shows the company's initials instead.
const _logos = <String, String>{
  'AIRTEL': 'airtel.jpg',
  'BHL': 'bhl.png',
  'CHL': 'chl.png',
  'FDHB': 'fdhb.png',
  'FMBCH': 'fmbch.png',
  'ICON': 'icon.png',
  'ILLOVO': 'illovo.png',
  'MPICO': 'mpico.jpg',
  'NBM': 'nbm.png',
  'NBS': 'nbs.png',
  'NICO': 'nico.png',
  'NITL': 'nitl.png',
  'OMU': 'omu.png',
  'PCL': 'pcl.png',
  'STANDARD': 'standard.png',
  'SUNBIRD': 'sunbird.png',
  'TNM': 'tnm.png',
};

/// The bundled logo for a ticker, or null when there is none.
String? mseLogoAsset(String? ticker) {
  final file = _logos[ticker?.trim().toUpperCase()];
  return file == null ? null : 'assets/mse_logos/$file';
}

/// A company's logo in a round frame, or its initials when there is no logo.
class MseLogo extends StatelessWidget {
  const MseLogo({super.key, required this.ticker, this.name, this.size = 40});

  final String? ticker;

  /// Used for the initials when there is no logo.
  final String? name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final asset = mseLogoAsset(ticker);

    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: scheme.primaryContainer, shape: BoxShape.circle),
      child: Text(
        _initials(name ?? ticker),
        style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w800, fontSize: size * 0.34),
      ),
    );

    if (asset == null) return fallback;

    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: ClipOval(
        child: Image.asset(
          asset,
          fit: BoxFit.contain,
          cacheWidth: (size * 3).round(),
          errorBuilder: (_, _, _) => fallback,
        ),
      ),
    );
  }

  static String _initials(String? text) {
    final words = (text ?? '').trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    if (words.length == 1) return words.first.substring(0, words.first.length.clamp(1, 2)).toUpperCase();
    return (words[0][0] + words[1][0]).toUpperCase();
  }
}
