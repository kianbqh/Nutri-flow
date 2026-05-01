import 'package:flutter/material.dart';

class AppSoftBackground extends StatelessWidget {
  const AppSoftBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned(
          top: -36,
          right: -28,
          child: _AppBackdropOrb(
            size: 180,
            colors: [Color(0xFFFFD7BA), Color(0x00FFD7BA)],
          ),
        ),
        const Positioned(
          top: 280,
          left: -70,
          child: _AppBackdropOrb(
            size: 170,
            colors: [Color(0xFFF8C29E), Color(0x00F8C29E)],
          ),
        ),
        const Positioned(
          bottom: -82,
          right: -52,
          child: _AppBackdropOrb(
            size: 210,
            colors: [Color(0xFFFFE7D2), Color(0x00FFE7D2)],
          ),
        ),
        child,
      ],
    );
  }
}

class AppSurfaceCard extends StatelessWidget {
  const AppSurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.color = Colors.white,
    this.borderRadius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: const Color(0xFFF1DDD0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0C3D1C0A),
            blurRadius: 18,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }
}

class AppHeroCard extends StatelessWidget {
  const AppHeroCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badges = const <Widget>[],
    this.footer,
    this.actions,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> badges;
  final Widget? footer;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF8B4D2A), Color(0xFFD78649), Color(0xFFF1C9A4)],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F8B4D2A),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppGlassChip(icon: icon, label: title),
              ...badges,
            ],
          ),
          const SizedBox(height: 18),
          Text(
            title,
            style: const TextStyle(
              fontSize: 28,
              height: 1.12,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
              color: Color(0xFFFFFAF6),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: Colors.white.withAlpha(230),
            ),
          ),
          if (actions != null && actions!.isNotEmpty) ...[
            const SizedBox(height: 18),
            Wrap(spacing: 10, runSpacing: 10, children: actions!),
          ],
          if (footer != null) ...[
            const SizedBox(height: 16),
            footer!,
          ],
        ],
      ),
    );
  }
}

class AppGlassChip extends StatelessWidget {
  const AppGlassChip({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(34),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withAlpha(54)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withAlpha(242),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

class AppSectionHeading extends StatelessWidget {
  const AppSectionHeading({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Color(0xFF2F2722),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.5,
            color: Color(0xFF7A6A5D),
          ),
        ),
      ],
    );
  }
}

class AppHintStrip extends StatelessWidget {
  const AppHintStrip({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(34),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withAlpha(44)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(30),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.center,
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: Colors.white.withAlpha(235),
                fontSize: 13.5,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppBackdropOrb extends StatelessWidget {
  const _AppBackdropOrb({required this.size, required this.colors});

  final double size;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: colors,
            stops: const [0.2, 1],
          ),
        ),
      ),
    );
  }
}