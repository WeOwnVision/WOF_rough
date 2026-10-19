import 'package:flutter/material.dart';

/// Fare tekerleğiyle kaydırmayı yumuşatan controller. Flutter web tekerleğin
/// her tıkında sayfayı bir anda zıplatır; bu controller aynı mesafeyi kısa
/// bir animasyonla gider. Art arda gelen tıklar hedefe eklenir, böylece
/// hızlı çevirmede animasyon baştan başlamaz.
class SmoothScrollController extends ScrollController {
  SmoothScrollController({super.initialScrollOffset, super.debugLabel});

  /// When true, acts as a plain [ScrollController] by delegating directly
  /// to [super.createScrollPosition] for A/B performance profiling.
  static bool usePlainController = true;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    if (usePlainController) {
      return super.createScrollPosition(physics, context, oldPosition);
    }
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
    // Dokunmatik yüzey (trackpad) ve yüksek hassasiyetli tekerlekler küçük ve sık adımlar
    // gönderir. Bunları doğrudan platform fiziğine bırakıyoruz; animasyon eklemek
    // tarayıcının kendi ivmelenmesiyle çatışıp takılmaya yol açar.
    if (delta.abs() < 40) {
      _target = null;
      super.pointerScroll(delta);
      return;
    }

    // Klasik kademeli fare tekerleği tıkları:
    final currentPixels = pixels;
    final base = (_target != null && isScrollingNotifier.value) ? _target! : currentPixels;
    final target = (base + delta).clamp(minScrollExtent, maxScrollExtent);
    if ((target - currentPixels).abs() < 0.5) return;
    _target = target;

    // Hızlı tıklandığında süre mesafeye göre orantılı ayarlanır, böylece kuyrukta birikip
    // gecikme (lag) hissi oluşturmaz. easeOutQuad ile ilk hız yüksek başlar.
    final remainingDist = (target - currentPixels).abs();
    final durationMs = (110 + (remainingDist * 0.18)).clamp(110, 220).toInt();

    animateTo(
      target,
      duration: Duration(milliseconds: durationMs),
      curve: Curves.easeOutQuad,
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
