import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/photo_files.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/actions.dart';
import '../../../shared/widgets/ui.dart';
import '../viewmodels/salon_view_model.dart';

/// Owner's photo strip: add from camera or gallery, pick the cover, remove.
/// The first photo is the cover clients see on cards and the salon page.
class SalonPhotos extends StatelessWidget {
  final SalonViewModel vm;
  const SalonPhotos({super.key, required this.vm});

  static final _picker = ImagePicker();

  List<String> get _photos => vm.salon?.photos ?? const [];

  Future<void> _add(BuildContext context) async {
    final left = maxSalonPhotos - _photos.length;
    final source = await showHSheet<ImageSource>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(tr('Add photos'), sub: tr('Show your chairs, work and storefront. Up to {n} more.', {'n': left})),
        HButton(tr('Take a photo'), icon: 'camera', block: true, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        HButton(tr('Choose from gallery'), icon: 'grid', block: true, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    );
    if (source == null) return;
    // Downscaled and compressed on pick, so photos stay small on the phone.
    final picked = source == ImageSource.camera
        ? [if (await _picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82) case final x?) x]
        : await _picker.pickMultiImage(maxWidth: 1600, imageQuality: 82, limit: left > 1 ? left : null);
    if (picked.isEmpty) return;
    await attempt(
      () async {
        final kept = [for (final x in picked.take(left)) await PhotoFiles.keep(x.path)];
        await vm.setPhotos([..._photos, ...kept]);
      },
      success: picked.length == 1 ? tr('Photo added') : tr('{n} photos added', {'n': picked.take(left).length}),
      icon: 'camera',
    );
  }

  Future<void> _open(BuildContext context, String name) async {
    final isCover = _photos.first == name;
    final choice = await showHSheet<String>(
      context,
      (ctx) => VStack(gap: 10, [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: SalonArt(0, photo: name, radius: 0),
          ),
        ),
        if (!isCover) HButton(tr('Make cover photo'), icon: 'star', block: true, onTap: () => Navigator.pop(ctx, 'cover')),
        HButton(tr('Remove photo'), icon: 'x', block: true, kind: BtnKind.dangerSoft, onTap: () => Navigator.pop(ctx, 'remove')),
      ]),
    );
    if (choice == 'cover') {
      await attempt(() => vm.setPhotos([name, ..._photos.where((p) => p != name)]), success: tr('Cover photo updated'), icon: 'star');
    } else if (choice == 'remove') {
      final ok = await attempt(() => vm.setPhotos(_photos.where((p) => p != name).toList()), success: tr('Photo removed'), icon: 'x');
      if (ok) await PhotoFiles.delete(name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final photos = _photos;
    Widget tile({required Widget child, VoidCallback? onTap}) => Tap(
      onTap: onTap,
      child: SizedBox(width: 104, height: 104, child: child),
    );
    return SizedBox(
      height: 104,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        children: [
          if (photos.length < maxSalonPhotos && PhotoFiles.available)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: tile(
                onTap: () => _add(context),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: c.brandSoft,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.brandLine, width: 1.5),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      HIcon('camera', size: 26, color: c.brandText),
                      const SizedBox(height: 6),
                      Text(
                        photos.isEmpty ? tr('Add photos') : tr('Add more'),
                        style: T.cap(context).copyWith(color: c.brandText, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          for (final (i, p) in photos.indexed)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Reveal(
                key: ValueKey(p),
                child: tile(
                  onTap: () => _open(context, p),
                  child: SalonArt(
                    0,
                    photo: p,
                    radius: 16,
                    child: i == 0
                        ? const Align(
                            alignment: Alignment.bottomLeft,
                            child: Padding(padding: EdgeInsets.all(6), child: _CoverTag()),
                          )
                        : null,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CoverTag extends StatelessWidget {
  const _CoverTag();
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(8)),
    child: Text(
      tr('Cover'),
      style: const TextStyle(fontFamily: T.f, fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
    ),
  );
}
