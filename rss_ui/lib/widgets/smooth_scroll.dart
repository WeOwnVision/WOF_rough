import 'package:flutter/material.dart';

/// Fare tekerleğiyle kaydırmayı yumuşatan controller. Flutter web tekerleğin
/// her tıkında sayfayı bir anda zıplatır; bu controller aynı mesafeyi kısa
/// bir animasyonla gider. Art arda gelen tıklar hedefe eklenir, böylece
/// hızlı çevirmede animasyon baştan başlamaz.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.initialScrollOffset, super.debugLabel});

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _SmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
    );
  }
}

class _SmoothScrollPosition extends ScrollPositionWithSingleContext {
  _SmoothScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  /// Süren animasyonun gittiği yer; yeni tık buradan devam eder.
  double? _target;

  @override
  void pointerScroll(double delta) {
    // Dokunmatik yüzey küçük ve sık adımlar gönderir, zaten akıcıdır.
    if (delta.abs() < 40) {
      _target = null;
      super.pointerScroll(delta);
      return;
    }
    final from = _target != null && isScrollingNotifier.value
        ? _target!
        : pixels;
    final target = (from + delta).clamp(minScrollExtent, maxScrollExtent);
    if (target == pixels) return;
    _target = target;
    animateTo(
      target,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
    );
  }
}

/// Kendi State'i olmayan bir yerde [SmoothScrollController] kullanmak için:
/// controller'ı oluşturur, iş bitince kapatır.
class SmoothScroll extends StatefulWidget {
  const SmoothScroll({super.key, required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<SmoothScroll> createState() => _SmoothScrollState();
}

class _SmoothScrollState extends State<SmoothScroll> {
  final _controller = SmoothScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
