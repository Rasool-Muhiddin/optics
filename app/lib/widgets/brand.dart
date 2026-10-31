import 'package:flutter/material.dart';

import '../core/strings/app_strings.dart';

/// Tera brand images (downscaled copies in `assets/images/brand/`).
class BrandAssets {
  const BrandAssets._();

  /// Full platform logo (mark + "TERA Software Solutions"), transparent background.
  static const logo = 'assets/images/brand/tera_logo.png';

  /// The same logo on a white background (used on dark surfaces, where the dark logo text
  /// would not be readable).
  static const logoOnWhite = 'assets/images/brand/tera_logo_on_white.png';

  /// The "T" mark only, transparent; readable on the dark sidebar and brand panel.
  static const mark = 'assets/images/brand/tera_mark.png';
}

/// Full Tera platform logo, square [size]. Light theme: transparent logo. Dark theme: the
/// white-background version as a rounded card (the logo's dark-teal text needs a light ground).
class BrandLogo extends StatelessWidget {
  const BrandLogo({super.key, this.size = 120});

  final double size;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final image = Image.asset(
      dark ? BrandAssets.logoOnWhite : BrandAssets.logo,
      width: size,
      height: size,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      semanticLabel: AppStrings.appTitle,
    );
    if (!dark) return image;
    return ClipRRect(borderRadius: BorderRadius.circular(size * 0.12), child: image);
  }
}

/// The Tera "T" mark alone, square [size] (sidebar header, brand panel).
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 40});

  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
    BrandAssets.mark,
    width: size,
    height: size,
    fit: BoxFit.contain,
    filterQuality: FilterQuality.medium,
    semanticLabel: AppStrings.appTitle,
  );
}
