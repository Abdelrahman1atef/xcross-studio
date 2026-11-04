import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../app/app_controller.dart';
import '../../app/services.dart';
import '../../design_system/design_system.dart';
import '../../src/cli/xcross_commands.dart';
import '../../src/cli/xcross_events.dart';
import '../../src/state/job.dart';
import '../common/job_views.dart';
import 'studio_panel.dart';

/// iOS's icon corner radius as a share of the side.
const _cornerShare = 0.2237;

/// Labels: body text, semibold.
final _label = XType.body.copyWith(fontWeight: FontWeight.w600);

/// App icon (features 023 and 024): every size iOS uses, checked by `xcross
/// icons check` and shown as iOS masks it; the studio designs icons and the
/// splash, and the CLI draws and writes them. The page reads the icon files
/// only to display them.
class IconsPage extends StatefulWidget {
  const IconsPage({super.key});

  @override
  State<IconsPage> createState() => _IconsPageState();
}

class _IconsPageState extends State<IconsPage> {
  IconsCheckReport? _report;
  Job? _checkJob;
  String? _checkedFor;

  /// File name → bytes, read after each check (the files change in place,
  /// so they are not loaded through the image cache by path).
  final Map<String, Uint8List> _images = {};
  bool _safeArea = true;

  bool _making = false;
  StudioResult? _result;

  Future<void> _check(String project) async {
    final services = Services.of(context);
    _checkedFor = project;
    IconsCheckReport? report;
    final job = services.jobs.run(
      'Check the app icon',
      XcrossCommands.iconsCheck(),
      workingDirectory: project,
      onEvent: (event) {
        if (event is IconsCheckReport) report = event;
      },
    );
    setState(() => _checkJob = job);
    await job.done;
    if (mounted) _apply(report);
  }

  void _apply(IconsCheckReport? report) {
    _images.clear();
    final path = report?.path;
    if (report != null && path != null) {
      for (final name in {
        for (final slot in report.slots) ?slot.file,
        ?report.source,
      }) {
        final file = File(p.join(path, name));
        if (file.existsSync()) _images[name] = file.readAsBytesSync();
      }
    }
    setState(() => _report = report);
  }

  @override
  Widget build(BuildContext context) {
    final services = Services.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([services.settings, services.app]),
      builder: (context, _) {
        final project = services.settings.projectPath;
        // The check runs when the page is first shown for a project.
        if (project != null &&
            project != _checkedFor &&
            services.app.destination == Destination.icons) {
          _checkedFor = project;
          _report = null;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _check(project);
          });
        }
        return WorkspaceLayout(
          title: 'App icon',
          subtitle:
              'One image makes every app icon and the native splash. iOS '
              'sizes are checked and shown as iOS masks them.',
          actions: [
            if (project != null)
              XButton(
                label: 'Check again',
                icon: Icons.refresh,
                variant: XButtonVariant.secondary,
                loading: _checkJob?.isRunning ?? false,
                loadingLabel: 'Checking…',
                onPressed: () => _check(project),
              ),
            XButton(
              label: 'Icon and splash studio…',
              icon: Icons.auto_fix_high_outlined,
              onPressed: () => setState(() => _making = true),
            ),
          ],
          children: [
            if (_making) ...[
              StudioPanel(
                // A project's saved design loads when the panel is made.
                key: ValueKey(project),
                project: project,
                onClose: () => setState(() => _making = false),
                onResult: (result) {
                  setState(() => _result = result);
                  if (result.toProject && project != null) _check(project);
                },
              ),
              _gap,
            ],
            if (project == null)
              const XEmptyState(
                icon: Icons.apps,
                title: 'Open a Flutter project',
                message:
                    'Choose a project on Overview to check its app icon and '
                    'write into it. The studio can export without one.',
              )
            else
              ..._content(context, project),
          ],
        );
      },
    );
  }

  List<Widget> _content(BuildContext context, String project) {
    final report = _report;
    final result = _result;
    return [
      if (result != null) ...[
        XCallout(
          title: result.message,
          status: XStatus.ready,
          children: const [],
        ),
        _gap,
      ],
      if (report == null)
        XCard(
          title: 'Checking the icon set',
          child: _checkJob == null
              ? const XNote('Starting…')
              : JobConsole(job: _checkJob!, height: 120, showTitle: false),
        )
      else if (report.path == null)
        XCallout(
          title: 'No app icon set',
          status: XStatus.failed,
          children: [
            Text(
              'ios/Runner/Assets.xcassets has no .appiconset. Make one from '
              'your logo in the Icon and splash studio.',
              style: XType.support,
            ),
          ],
        )
      else ...[
        _previewCard(context, report),
        _gap,
        _sizesCard(report),
        _gap,
        _issuesCard(report),
      ],
    ];
  }

  static const _gap = SizedBox(height: XSpace.s3);

  /// The image iOS uses for [role]: the iPhone slot with the largest scale,
  /// else the App Store icon.
  Uint8List? _imageFor(IconsCheckReport report, String role) {
    final slots =
        report.slots
            .where((s) => s.role == role && s.status == 'ok' && s.file != null)
            .toList()
          ..sort((a, b) => b.scale.compareTo(a.scale));
    for (final slot in slots) {
      final bytes = _images[slot.file];
      if (bytes != null) return bytes;
    }
    return report.source == null ? null : _images[report.source];
  }

  Widget _previewCard(BuildContext context, IconsCheckReport report) {
    final services = Services.of(context);
    final name = p.basename(services.settings.projectPath ?? 'App');
    final master = report.source == null ? null : _images[report.source];
    return XCard(
      title: 'How iOS shows it',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Safe area', style: XType.support),
          Switch(
            value: _safeArea,
            onChanged: (value) => setState(() => _safeArea = value),
          ),
        ],
      ),
      child: Wrap(
        spacing: XSpace.s4,
        runSpacing: XSpace.s4,
        children: [
          _Labeled(
            label: 'App Store icon, 1024 px',
            child: _SafeAreaPreview(
              icon: master,
              placement: report.placement,
              show: _safeArea,
            ),
          ),
          _Labeled(
            label: 'Home screen',
            child: _HomeScreen(
              icon: _imageFor(report, 'home'),
              name: name,
              dark: false,
            ),
          ),
          _Labeled(
            label: 'Home screen, dark',
            child: _HomeScreen(
              icon: _imageFor(report, 'home'),
              name: name,
              dark: true,
            ),
          ),
          _Labeled(
            label: 'Notification',
            child: _NotificationBanner(
              icon: _imageFor(report, 'notification'),
              name: name,
            ),
          ),
          _Labeled(
            label: 'Settings',
            child: _SettingsRow(
              icon: _imageFor(report, 'settings'),
              name: name,
            ),
          ),
          _Labeled(
            label: 'Spotlight',
            child: _Spotlight(icon: _imageFor(report, 'spotlight'), name: name),
          ),
          _Labeled(
            label: 'App Store',
            child: _AppStoreCard(icon: master, name: name),
          ),
        ],
      ),
    );
  }

  Widget _sizesCard(IconsCheckReport report) {
    final groups = <String, List<IconSlotStatus>>{};
    for (final slot in report.slots) {
      final group = switch (slot.idiom) {
        'iphone' => 'iPhone',
        'ipad' => 'iPad',
        'universal' => 'Every size is made from this image',
        _ => 'App Store',
      };
      (groups[group] ??= []).add(slot);
    }
    final missing = report.slots.where((s) => s.status != 'ok').length;
    return XCard(
      title: 'Every size',
      subtitle: report.style == 'single-size'
          ? 'Single-size icon (Xcode 14+)'
          : '${report.slots.length} slots · ${p.basename(report.path!)}',
      trailing: XStatusBadge(
        status: missing == 0 ? XStatus.ready : XStatus.failed,
        label: missing == 0 ? 'All present' : '$missing to fix',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final MapEntry(key: group, value: slots) in groups.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: XSpace.s2, bottom: XSpace.s2),
              child: Text(group, style: _label),
            ),
            Wrap(
              spacing: XSpace.s3,
              runSpacing: XSpace.s3,
              children: [
                for (final slot in slots)
                  _SlotTile(
                    slot: slot,
                    image: slot.file == null ? null : _images[slot.file],
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _issuesCard(IconsCheckReport report) {
    final ordered = [
      for (final severity in const ['error', 'warning', 'info'])
        ...report.issues.where((issue) => issue.severity == severity),
    ];
    return XCard(
      title: 'Checks',
      subtitle: _placementText(report.placement),
      trailing: XStatusBadge(
        status: report.errors > 0
            ? XStatus.failed
            : report.warnings > 0
            ? XStatus.warning
            : XStatus.ready,
        label: report.errors == 0 && report.warnings == 0
            ? 'Ready'
            : '${report.errors} errors, ${report.warnings} warnings',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (ordered.isEmpty)
            const XNote(
              'Every size is present at the right size, without '
              'transparency, and the logo sits inside the corners.',
            ),
          for (final issue in ordered)
            XCheckRow(
              status: switch (issue.severity) {
                'error' => XStatus.failed,
                'warning' => XStatus.warning,
                _ => XStatus.idle,
              },
              label: '[${issue.code}] ${issue.message}',
              detail: issue.hint,
            ),
        ],
      ),
    );
  }

  static String? _placementText(IconPlacementInfo? placement) {
    if (placement == null) return null;
    if (placement.fullBleed) {
      return 'Full-bleed artwork (placement not measured)';
    }
    final box = placement.box;
    if (box == null) return 'Background ${placement.background}, no logo';
    final centred =
        placement.offset.dx.abs() <= 0.03 && placement.offset.dy.abs() <= 0.03;
    return 'Background ${placement.background} · logo '
        '${(box.width * 100).round()}% × ${(box.height * 100).round()}% · '
        '${centred ? 'centred' : 'off centre'} · '
        '${placement.outsideMask > 0.002 ? 'cut by the corners' : 'inside the corners'}';
  }
}

/// [child] with a caption under it.
class _Labeled extends StatelessWidget {
  const _Labeled({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      child,
      const SizedBox(height: XSpace.s1),
      Text(label, style: XType.support),
    ],
  );
}

/// The iOS icon shape.
ShapeBorder _iconShape(double size) => RoundedSuperellipseBorder(
  borderRadius: BorderRadius.circular(size * _cornerShare),
);

/// [icon] cut to the iOS icon shape at [size] logical pixels.
class _MaskedIcon extends StatelessWidget {
  const _MaskedIcon({required this.icon, required this.size});

  final Uint8List? icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    return SizedBox.square(
      dimension: size,
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: _iconShape(size)),
        child: icon == null
            ? ColoredBox(
                color: c.border,
                child: Icon(
                  Icons.image_not_supported_outlined,
                  size: size * 0.4,
                  color: c.textMuted,
                ),
              )
            : Image.memory(
                icon!,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                gaplessPlayback: true,
              ),
      ),
    );
  }
}

/// The 1024 px icon large, what the corners cut shown faintly, and the
/// safe-area guides: the mask outline, the centre lines and the measured
/// logo box.
class _SafeAreaPreview extends StatelessWidget {
  const _SafeAreaPreview({
    required this.icon,
    required this.placement,
    required this.show,
  });

  static const size = 220.0;

  final Uint8List? icon;
  final IconPlacementInfo? placement;
  final bool show;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final warn =
        placement != null &&
        (placement!.outsideMask > 0.002 ||
            placement!.offset.dx.abs() > 0.03 ||
            placement!.offset.dy.abs() > 0.03);
    return SizedBox.square(
      dimension: size,
      child: Stack(
        children: [
          if (show && icon != null)
            Opacity(
              opacity: 0.25,
              child: Image.memory(icon!, width: size, height: size),
            ),
          _MaskedIcon(icon: icon, size: size),
          if (show)
            CustomPaint(
              size: const Size.square(size),
              painter: _GuidesPainter(
                box: placement?.box,
                outline: c.primary,
                boxColor: warn ? c.warning : c.success,
              ),
            ),
        ],
      ),
    );
  }
}

class _GuidesPainter extends CustomPainter {
  _GuidesPainter({
    required this.box,
    required this.outline,
    required this.boxColor,
  });

  final ({double left, double top, double width, double height})? box;
  final Color outline;
  final Color boxColor;

  @override
  void paint(Canvas canvas, Size size) {
    final side = size.width;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = outline;
    // The superellipse |x|⁵ + |y|⁵ = 1 that `icons check` measures with.
    final path = Path();
    for (var i = 0; i <= 360; i++) {
      final t = i * math.pi / 180;
      final c = math.cos(t);
      final s = math.sin(t);
      final x = c.sign * math.pow(c.abs(), 2 / 5) * side / 2 + side / 2;
      final y = s.sign * math.pow(s.abs(), 2 / 5) * side / 2 + side / 2;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, stroke);
    final guide = Paint()
      ..strokeWidth = 1
      ..color = outline.withValues(alpha: 0.5);
    canvas
      ..drawLine(Offset(side / 2, 0), Offset(side / 2, side), guide)
      ..drawLine(Offset(0, side / 2), Offset(side, side / 2), guide);
    final logo = box;
    if (logo != null) {
      canvas.drawRect(
        Rect.fromLTWH(
          logo.left * side,
          logo.top * side,
          logo.width * side,
          logo.height * side,
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = boxColor,
      );
    }
  }

  @override
  bool shouldRepaint(_GuidesPainter oldDelegate) =>
      oldDelegate.box != box ||
      oldDelegate.outline != outline ||
      oldDelegate.boxColor != boxColor;
}

/// A wallpaper with the app among placeholder icons.
class _HomeScreen extends StatelessWidget {
  const _HomeScreen({
    required this.icon,
    required this.name,
    required this.dark,
  });

  final Uint8List? icon;
  final String name;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    Widget placeholder() => Container(
      width: 60,
      height: 60,
      decoration: ShapeDecoration(
        color: Colors.white.withValues(alpha: dark ? 0.12 : 0.35),
        shape: _iconShape(60),
      ),
    );
    Widget cell(Widget icon, String label) => SizedBox(
      width: 72,
      child: Column(
        children: [
          icon,
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              shadows: [Shadow(blurRadius: 3, color: Colors.black54)],
            ),
          ),
        ],
      ),
    );
    return Container(
      width: 240,
      height: 150,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF0B1A3A), Color(0xFF3A1452)]
              : const [Color(0xFF7FB2F0), Color(0xFFF2A7C3)],
        ),
      ),
      alignment: Alignment.center,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          cell(placeholder(), ''),
          cell(_MaskedIcon(icon: icon, size: 60), name),
          cell(placeholder(), ''),
        ],
      ),
    );
  }
}

class _NotificationBanner extends StatelessWidget {
  const _NotificationBanner({required this.icon, required this.name});

  final Uint8List? icon;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 330,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MaskedIcon(icon: icon, size: 36),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const Text(
                    'now',
                    style: TextStyle(color: Color(0xFF8A8A8E), fontSize: 12),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Order paid',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Text(
                'Your order has been paid.',
                style: TextStyle(color: Colors.black, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({required this.icon, required this.name});

  final Uint8List? icon;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 260,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Row(
      children: [
        _MaskedIcon(icon: icon, size: 29),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.black, fontSize: 15),
          ),
        ),
        const Icon(Icons.chevron_right, color: Color(0xFFC4C4C7), size: 20),
      ],
    ),
  );
}

class _Spotlight extends StatelessWidget {
  const _Spotlight({required this.icon, required this.name});

  final Uint8List? icon;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 120,
    height: 100,
    decoration: BoxDecoration(
      color: const Color(0xFF2C2C2E),
      borderRadius: BorderRadius.circular(14),
    ),
    alignment: Alignment.center,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MaskedIcon(icon: icon, size: 40),
        const SizedBox(height: 6),
        Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
      ],
    ),
  );
}

class _AppStoreCard extends StatelessWidget {
  const _AppStoreCard({required this.icon, required this.name});

  final Uint8List? icon;
  final String name;

  @override
  Widget build(BuildContext context) => Container(
    width: 280,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        _MaskedIcon(icon: icon, size: 64),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFEFEFF4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Text(
            'GET',
            style: TextStyle(
              color: Color(0xFF0A84FF),
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );
}

/// One slot: its image at up to 56 logical pixels, role, size and status.
class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.slot, required this.image});

  final IconSlotStatus slot;
  final Uint8List? image;

  @override
  Widget build(BuildContext context) {
    final c = XTheme.of(context).colors;
    final shown = math.min(56, slot.pixels).toDouble();
    final status = switch (slot.status) {
      'ok' => XStatus.ready,
      'missing' when !slot.required => XStatus.warning,
      _ => XStatus.failed,
    };
    return Container(
      width: 150,
      padding: const EdgeInsets.all(XSpace.s2),
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(XRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 56,
            child: Align(
              alignment: Alignment.centerLeft,
              child: image == null
                  ? Icon(Icons.image_not_supported_outlined, color: c.textMuted)
                  : Image.memory(
                      image!,
                      width: shown,
                      height: shown,
                      filterQuality: FilterQuality.medium,
                      gaplessPlayback: true,
                    ),
            ),
          ),
          const SizedBox(height: XSpace.s1),
          Text(slot.label, style: _label),
          Text(
            slot.idiom == 'ios-marketing' || slot.idiom == 'universal'
                ? '${slot.pixels} px'
                : '${slot.pointsText} pt @${slot.scale}x · ${slot.pixels} px',
            style: XType.support,
          ),
          const SizedBox(height: XSpace.s1),
          XStatusBadge(
            status: status,
            label: switch (slot.status) {
              'ok' => 'OK',
              'wrong_size' => 'Is ${slot.actual}',
              'unreadable' => 'Not a PNG',
              _ => 'Missing',
            },
          ),
        ],
      ),
    );
  }
}
