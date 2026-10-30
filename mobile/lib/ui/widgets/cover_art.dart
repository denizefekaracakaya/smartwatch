import 'package:flutter/material.dart';

import '../../api/models.dart';
import '../theme.dart';

/// Stand-in artwork for tracks, artists and playlists (the catalog has no images).
///
/// The colour is derived from [seed] (album or artist name), so every song of an album shares a cover and
/// every artist keeps the same colour across screens. The label is the artist's initials, set like the
/// print on a record sleeve.
class CoverArt extends StatelessWidget {
  const CoverArt({
    super.key,
    required this.seed,
    required this.label,
    required this.size,
    this.circle = false,
    this.icon,
    this.caption,
  });

  factory CoverArt.track(Track track, {required double size, Key? key}) =>
      CoverArt(
        key: key,
        seed: track.album ?? track.artist,
        label: track.artist,
        size: size,
        icon: track.kind == TrackKind.podcast ? Icons.podcasts : null,
        caption: track.album ?? track.title,
      );

  final String seed;
  final String label;
  final double size;
  final bool circle;
  final IconData? icon;

  /// Small text printed at the top of large covers (album or title), like the spine of a sleeve.
  final String? caption;

  static Color colorFor(String seed) {
    // FNV-1a: stable across runs and platforms, unlike String.hashCode.
    var hash = 0x811c9dc5;
    for (final unit in seed.toLowerCase().codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return AppColors.coverColors[hash % AppColors.coverColors.length];
  }

  static String initials(String name) {
    final words =
        name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return '?';
    final letters =
        words.length == 1
            ? words.first.characters.take(2).toString()
            : words.take(2).map((w) => w.characters.first).join();
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final color = colorFor(seed);
    final radius = circle ? size / 2 : (size < 64 ? 4.0 : 8.0);
    final small = size < 64;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
        // A faint inner ring gives the flat colour some depth without a gradient.
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.18),
          width: small ? 0.5 : 1,
        ),
      ),
      padding: EdgeInsets.all(circle ? 0 : size * 0.09),
      alignment: circle || small ? Alignment.center : Alignment.bottomLeft,
      child:
          icon != null && small
              ? Icon(
                icon,
                size: size * 0.45,
                color: Colors.white.withValues(alpha: 0.85),
              )
              : caption != null && size >= 160
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    caption!.toUpperCase(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: size * 0.045,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.6,
                    ),
                  ),
                  const Spacer(),
                  _initialsText(),
                ],
              )
              : _initialsText(),
    );
  }

  Widget _initialsText() {
    final small = size < 64;
    return Text(
      initials(label),
      maxLines: 1,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.88),
        fontSize: size * (circle ? 0.34 : (small ? 0.36 : 0.22)),
        fontWeight: FontWeight.w800,
        letterSpacing: small ? 0 : -1,
        height: 1,
      ),
    );
  }
}
