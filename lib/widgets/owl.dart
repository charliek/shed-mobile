import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Bundled owl artwork (the design's `assets/owl-*.svg`). The in-app owl carries
/// gold eyes — distinct from the green-eyed app *icon* — so it's kept as a
/// separate asset set under `assets/owl/`.
abstract final class OwlAssets {
  static const orange = 'assets/owl/owl-orange.svg'; // light-mode logo
  static const amber = 'assets/owl/owl-amber.svg'; // dark-mode logo, terminal
  static const ink = 'assets/owl/owl-ink.svg'; // light-mode empty-state ghost
  static const white =
      'assets/owl/owl-white.svg'; // dark-mode empty-state ghost
}

/// The owl drawing is 861×709; width drives height so it never distorts.
const double _owlAspect = 861 / 709;

/// The Shed owl logo, tinted for the active theme (orange on light, amber on
/// dark). [width] sets the size; height follows the artwork's aspect ratio.
class OwlLogo extends StatelessWidget {
  const OwlLogo({super.key, this.width = 26});

  final double width;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SvgPicture.asset(
      dark ? OwlAssets.amber : OwlAssets.orange,
      width: width,
      height: width / _owlAspect,
      semanticsLabel: 'Shed',
    );
  }
}

/// A faded owl for empty states (ink on light, white on dark).
class OwlGhost extends StatelessWidget {
  const OwlGhost({super.key, this.width = 64, this.opacity = 0.5});

  final double width;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Opacity(
      opacity: opacity,
      child: SvgPicture.asset(
        dark ? OwlAssets.white : OwlAssets.ink,
        width: width,
        height: width / _owlAspect,
      ),
    );
  }
}
