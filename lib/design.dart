import 'package:flutter/material.dart';
import 'domain.dart';

const plum = Color(0xFF49374F);
const lilac = Color(0xFF8E72B1);
const rose = Color(0xFFCF849B);
const sage = Color(0xFF54816D);
const peach = Color(0xFFC1885E);

ThemeData appTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: lilac, brightness: brightness)
      .copyWith(
        primary: dark ? const Color(0xFFD5BDEC) : const Color(0xFF84649F),
        secondary: dark ? const Color(0xFFECAFC1) : rose,
        surface: dark ? const Color(0xFF302536) : const Color(0xFFFFFDFC),
        onSurface: dark ? const Color(0xFFF5EAF5) : plum,
        onSurfaceVariant: dark
            ? const Color(0xFFBFAFC6)
            : const Color(0xFF897A8E),
        outlineVariant: dark
            ? const Color(0xFF4B3B53)
            : const Color(0xFFF0E7EF),
      );
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: dark
        ? const Color(0xFF211B28)
        : const Color(0xFFFAF7F5),
    fontFamily: 'Tajawal',
    textTheme: TextTheme(
      headlineLarge: TextStyle(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        height: 1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
        height: 1.3,
      ),
      titleLarge: TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      titleMedium: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
      bodyLarge: TextStyle(fontSize: 16, color: scheme.onSurface, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, color: scheme.onSurface, height: 1.4),
      bodySmall: TextStyle(
        fontSize: 12,
        color: scheme.onSurfaceVariant,
        height: 1.4,
      ),
      labelLarge: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, thickness: 1),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF392D40) : const Color(0xFFF7F2F7),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.primary),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: scheme.error),
      ),
      labelStyle: TextStyle(color: scheme.onSurfaceVariant),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 17),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: dark ? const Color(0xFF30213C) : Colors.white,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFFE4CDEA) : plum,
      contentTextStyle: TextStyle(
        fontFamily: 'Tajawal',
        color: dark ? plum : Colors.white,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
    ),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

bool reducedMotion(BuildContext context) =>
    MediaQuery.disableAnimationsOf(context);
Duration motion(BuildContext context, int ms) =>
    Duration(milliseconds: reducedMotion(context) ? 0 : ms);
Color softTint(BuildContext context, Color color, [double opacity = .11]) =>
    color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark
          ? opacity * 1.6
          : opacity,
    );

class FlowerMark extends StatelessWidget {
  const FlowerMark({super.key, this.size = 46});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: size,
    height: size,
    child: CustomPaint(
      painter: _FlowerPainter(Theme.of(context).colorScheme.primary, rose),
    ),
  );
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter(this.a, this.b);
  final Color a, b;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    final s = size.width;
    paint.color = a.withValues(alpha: .28);
    canvas.drawOval(Rect.fromLTWH(s * .1, s * .08, s * .47, s * .48), paint);
    paint.color = b.withValues(alpha: .65);
    canvas.drawOval(Rect.fromLTWH(s * .47, s * .08, s * .44, s * .48), paint);
    paint.color = b.withValues(alpha: .3);
    canvas.drawOval(Rect.fromLTWH(s * .1, s * .45, s * .47, s * .48), paint);
    paint.color = a.withValues(alpha: .7);
    canvas.drawOval(Rect.fromLTWH(s * .47, s * .45, s * .44, s * .48), paint);
    paint.color = a;
    canvas.drawCircle(Offset(s * .505, s * .505), s * .085, paint);
  }

  @override
  bool shouldRepaint(_FlowerPainter old) => a != old.a || b != old.b;
}

class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.radius = 24,
  });
  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool pressed = false;
  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: pressed ? .98 : 1,
    duration: motion(context, 110),
    child: Listener(
      onPointerDown: (_) {
        if (widget.onTap != null) setState(() => pressed = true);
      },
      onPointerUp: (_) => setState(() => pressed = false),
      onPointerCancel: (_) => setState(() => pressed = false),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(widget.radius),
          onTap: widget.onTap,
          child: widget.child,
        ),
      ),
    ),
  );
}

class Entrance extends StatefulWidget {
  const Entrance({super.key, required this.child, this.delay = 0});
  final Widget child;
  final int delay;
  @override
  State<Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<Entrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
  );
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      if (reducedMotion(context)) {
        controller.value = 1;
      } else {
        Future<void>.delayed(Duration(milliseconds: widget.delay), () {
          if (mounted) controller.forward();
        });
      }
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: controller,
    child: ScaleTransition(
      scale: controller.drive(
        Tween(
          begin: .96,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
      ),
      child: widget.child,
    ),
  );
}

class MoneyCounter extends StatefulWidget {
  const MoneyCounter({
    super.key,
    required this.value,
    this.style,
    this.startAtZero = true,
  });
  final int value;
  final TextStyle? style;
  final bool startAtZero;
  @override
  State<MoneyCounter> createState() => _MoneyCounterState();
}

class _MoneyCounterState extends State<MoneyCounter>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this);
  late Animation<double> value;
  bool initialized = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!initialized) {
      initialized = true;
      value =
          Tween<double>(
            begin: widget.startAtZero && !reducedMotion(context)
                ? 0
                : widget.value.toDouble(),
            end: widget.value.toDouble(),
          ).animate(
            CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
          );
      controller.duration = motion(context, 450);
      controller.forward();
    } else if (reducedMotion(context)) {
      controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(MoneyCounter old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      value = Tween<double>(begin: value.value, end: widget.value.toDouble())
          .animate(
            CurvedAnimation(parent: controller, curve: Curves.easeOutCubic),
          );
      controller.duration = motion(context, 450);
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: '${moneyText(widget.value)} ريال سعودي',
    child: ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Directionality(
          textDirection: TextDirection.ltr,
          child: Text(
            moneyText(value.value.round()),
            maxLines: 1,
            overflow: TextOverflow.visible,
            style: widget.style,
          ),
        ),
      ),
    ),
  );
}

class MoneyLine extends StatelessWidget {
  const MoneyLine(
    this.value, {
    super.key,
    this.size = 25,
    this.color,
    this.animated = true,
  });
  final int value;
  final double size;
  final Color? color;
  final bool animated;
  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.ltr,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: animated
                ? MoneyCounter(
                    value: value,
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: FontWeight.w700,
                      color: color ?? Theme.of(context).colorScheme.onSurface,
                      height: 1.25,
                    ),
                  )
                : Text(
                    moneyText(value),
                    style: TextStyle(
                      fontSize: size,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                  ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          'SAR',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
    this.border = true,
  });
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final bool border;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(24),
      border: border
          ? Border.all(
              color: Theme.of(
                context,
              ).colorScheme.outlineVariant.withValues(alpha: .7),
            )
          : null,
      boxShadow: [
        BoxShadow(
          color: plum.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark ? 0 : .025,
          ),
          blurRadius: 22,
          offset: const Offset(0, 7),
        ),
      ],
    ),
    child: child,
  );
}

IconData statusIcon(OrderStatus status) => switch (status) {
  OrderStatus.pending => Icons.schedule_rounded,
  OrderStatus.arrived => Icons.check_circle_outline_rounded,
  OrderStatus.cancelled => Icons.close_rounded,
};
Color statusColor(OrderStatus status) => switch (status) {
  OrderStatus.pending => lilac,
  OrderStatus.arrived => sage,
  OrderStatus.cancelled => rose,
};

class StatusBadge extends StatelessWidget {
  const StatusBadge({
    super.key,
    required this.status,
    this.onChanged,
    this.enabled = true,
  });
  final OrderStatus status;
  final ValueChanged<OrderStatus>? onChanged;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    final badge = AnimatedContainer(
      duration: motion(context, 220),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: softTint(context, c),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedSwitcher(
            duration: motion(context, 220),
            transitionBuilder: (child, a) => ScaleTransition(
              scale: a,
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Icon(
              statusIcon(status),
              key: ValueKey(status),
              size: 16,
              color: c,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).brightness == Brightness.dark
                    ? Color.lerp(c, Colors.white, .35)
                    : c,
              ),
            ),
          ),
          if (onChanged != null) ...[
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 15, color: c),
          ],
        ],
      ),
    );
    if (onChanged == null) return badge;
    return PopupMenuButton<OrderStatus>(
      enabled: enabled,
      tooltip: 'تغيير حالة الطلب',
      onSelected: onChanged,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      itemBuilder: (context) => OrderStatus.values
          .map(
            (s) => PopupMenuItem(
              value: s,
              height: MediaQuery.textScalerOf(context).scale(48),
              child: Row(
                children: [
                  Icon(statusIcon(s), color: statusColor(s), size: 19),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.label)),
                  if (s == status) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check_rounded, size: 18),
                  ],
                ],
              ),
            ),
          )
          .toList(),
      child: badge,
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
    this.button,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? action;
  final String? button;
  @override
  Widget build(BuildContext context) => Entrance(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 94,
            height: 94,
            decoration: BoxDecoration(
              color: softTint(context, lilac, .09),
              borderRadius: BorderRadius.circular(32),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  size: 38,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const Positioned(
                  top: 15,
                  left: 16,
                  child: Icon(Icons.auto_awesome, size: 15, color: rose),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (action != null) ...[
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: action,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: Text(button!),
            ),
          ],
        ],
      ),
    ),
  );
}
