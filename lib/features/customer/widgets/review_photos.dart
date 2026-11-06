import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';

import '../../../domain/entities/entities.dart';
import '../../../domain/repositories/repositories.dart';
import '../../../shared/widgets/ui.dart';

/// Most photos on one review (HOLA's limit).
const maxReviewPhotos = 6;

String reviewPhotoLabel(String kind) => switch (kind) {
  'BEFORE' => tr('Before'),
  'AFTER' => tr('After'),
  _ => tr('Photo'),
};

/// Picks before/after photos for a review: (path, BEFORE | AFTER | OTHER).
class ReviewPhotoPicker extends StatelessWidget {
  const ReviewPhotoPicker({super.key, required this.photos, required this.onChanged});
  final List<(String, String)> photos;
  final ValueChanged<List<(String, String)>> onChanged;

  Future<void> _add(BuildContext context, String kind) async {
    final left = maxReviewPhotos - photos.length;
    if (left <= 0) return;
    final source = await showHSheet<ImageSource>(
      context,
      (ctx) => VStack(gap: 10, [
        SheetHead(
          kind == 'BEFORE'
              ? tr('Add a before photo')
              : kind == 'AFTER'
              ? tr('Add an after photo')
              : tr('Add photos'),
        ),
        HButton(tr('Take a photo'), icon: 'camera', block: true, onTap: () => Navigator.pop(ctx, ImageSource.camera)),
        HButton(tr('Choose from gallery'), icon: 'grid', block: true, kind: BtnKind.secondary, onTap: () => Navigator.pop(ctx, ImageSource.gallery)),
      ]),
    );
    if (source == null) return;
    final picker = ImagePicker();
    // Downscaled JPEGs: small to upload, and a format HOLA accepts.
    final picked = source == ImageSource.camera || kind != 'OTHER'
        ? [if (await picker.pickImage(source: source, maxWidth: 1600, imageQuality: 82) case final x?) x]
        : await picker.pickMultiImage(maxWidth: 1600, imageQuality: 82, limit: left > 1 ? left : null);
    if (picked.isEmpty) return;
    onChanged([...photos, for (final x in picked.take(left)) (x.path, kind)]);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final full = photos.length >= maxReviewPhotos;
    Widget addTile(String kind, String label) => Tap(
      onTap: full ? null : () => _add(context, kind),
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: c.line),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HIcon('camera', size: 22, color: full ? c.subtle : c.brandText),
            const SizedBox(height: 4),
            Text(
              label,
              style: T.cap(context).copyWith(color: full ? c.subtle : c.ink, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(tr('Photos (optional)'), style: HField.labelStyle(context)),
        const SizedBox(height: 4),
        Text(tr('Show the result: add a before and an after photo. Up to {n}.', {'n': maxReviewPhotos}), style: T.cap(context)),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (i, (path, kind)) in photos.indexed) ...[
                _Thumb(
                  image: Image.file(File(path), fit: BoxFit.cover),
                  label: reviewPhotoLabel(kind),
                  onRemove: () => onChanged([...photos]..removeAt(i)),
                ),
                const SizedBox(width: 10),
              ],
              if (!photos.any((p) => p.$2 == 'BEFORE')) ...[addTile('BEFORE', tr('Before')), const SizedBox(width: 10)],
              if (!photos.any((p) => p.$2 == 'AFTER')) ...[addTile('AFTER', tr('After')), const SizedBox(width: 10)],
              addTile('OTHER', tr('More')),
            ],
          ),
        ),
      ],
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb({required this.image, required this.label, this.onRemove, this.onTap, this.size = 84});
  final Widget image;
  final String label;
  final VoidCallback? onRemove, onTap;
  final double size;
  @override
  Widget build(BuildContext context) => Tap(
    onTap: onTap,
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(borderRadius: BorderRadius.circular(14), child: image),
          PositionedDirectional(
            start: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), borderRadius: BorderRadius.circular(6)),
              child: Text(
                label,
                style: T.cap(context).copyWith(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 10.5),
              ),
            ),
          ),
          if (onRemove != null)
            PositionedDirectional(
              top: 4,
              end: 4,
              child: Tap(
                onTap: onRemove,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(color: Colors.black.withValues(alpha: .6), shape: BoxShape.circle),
                  alignment: Alignment.center,
                  child: const HIcon('x', size: 14, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}

/// A review's photos as a row of thumbnails; tapping opens them full screen.
class ReviewPhotoStrip extends StatelessWidget {
  const ReviewPhotoStrip(this.review, {super.key});
  final Review review;
  @override
  Widget build(BuildContext context) {
    final engage = context.read<EngagementRepository>();
    // Before first, then after, then the rest.
    int rank(ReviewPhoto p) => p.kind == 'BEFORE' ? 0 : (p.kind == 'AFTER' ? 1 : 2);
    final photos = [...review.photos]..sort((a, b) => rank(a).compareTo(rank(b)));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          for (final (i, p) in photos.indexed) ...[
            _Thumb(
              size: 92,
              image: _ReviewImage(p, engage: engage),
              label: reviewPhotoLabel(p.kind),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => _Viewer(photos: photos, start: i, engage: engage),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _ReviewImage extends StatefulWidget {
  const _ReviewImage(this.photo, {required this.engage, this.fit = BoxFit.cover});
  final ReviewPhoto photo;
  final EngagementRepository engage;
  final BoxFit fit;
  @override
  State<_ReviewImage> createState() => _ReviewImageState();
}

class _ReviewImageState extends State<_ReviewImage> {
  late Future<File?> _file = widget.engage.reviewPhotoFile(widget.photo);
  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: _file,
    builder: (context, s) {
      final f = s.data;
      if (f != null) return Image.file(f, fit: widget.fit);
      return Container(
        color: context.c.bg2,
        alignment: Alignment.center,
        child: s.connectionState == ConnectionState.waiting
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : Tap(
                onTap: () => setState(() => _file = widget.engage.reviewPhotoFile(widget.photo)),
                child: HIcon('camera', size: 22, color: context.c.subtle),
              ),
      );
    },
  );
}

class _Viewer extends StatelessWidget {
  const _Viewer({required this.photos, required this.start, required this.engage});
  final List<ReviewPhoto> photos;
  final int start;
  final EngagementRepository engage;
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: Stack(
      children: [
        PageView(
          controller: PageController(initialPage: start),
          children: [
            for (final p in photos)
              Stack(
                children: [
                  InteractiveViewer(
                    maxScale: 5,
                    child: Center(
                      child: _ReviewImage(p, engage: engage, fit: BoxFit.contain),
                    ),
                  ),
                  Positioned(
                    bottom: MediaQuery.paddingOf(context).bottom + 20,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(reviewPhotoLabel(p.kind), style: T.ttl(context).copyWith(color: Colors.white)),
                    ),
                  ),
                ],
              ),
          ],
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 8,
          left: 8,
          child: IconBtn('x', onBand: true, onTap: () => Navigator.of(context).pop()),
        ),
      ],
    ),
  );
}
