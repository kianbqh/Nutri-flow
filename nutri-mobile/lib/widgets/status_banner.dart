import 'package:flutter/material.dart';

class StatusBanner extends StatelessWidget {
  const StatusBanner({
    super.key,
    required this.status,
    this.message,
  });

  final String status;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final cfg = _config(status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cfg.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cfg.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(cfg.icon, color: cfg.fg, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cfg.title, style: TextStyle(color: cfg.fg, fontWeight: FontWeight.w600)),
                if (message != null && message!.trim().isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: const TextStyle(color: Colors.black87)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  _StatusConfig _config(String s) {
    switch (s) {
      case 'COMPLETED':
        return _StatusConfig(
          title: '分析完成',
          fg: const Color(0xFF2E9B5F),
          bg: const Color(0xFFEAF7EF),
          border: const Color(0xFFCBEBD7),
          icon: Icons.check_circle_outline,
        );
      case 'FAILED':
        return _StatusConfig(
          title: '分析失败',
          fg: const Color(0xFFD9534F),
          bg: const Color(0xFFFDEDEC),
          border: const Color(0xFFF6C9C7),
          icon: Icons.error_outline,
        );
      case 'TIMEOUT':
        return _StatusConfig(
          title: '查询超时',
          fg: const Color(0xFFE2A93B),
          bg: const Color(0xFFFFF7E7),
          border: const Color(0xFFF5DFAC),
          icon: Icons.schedule,
        );
      default:
        return _StatusConfig(
          title: '分析中',
          fg: const Color(0xFFE97A3A),
          bg: const Color(0xFFFFF1E8),
          border: const Color(0xFFF8D2BA),
          icon: Icons.hourglass_top,
        );
    }
  }
}

class _StatusConfig {
  _StatusConfig({
    required this.title,
    required this.fg,
    required this.bg,
    required this.border,
    required this.icon,
  });

  final String title;
  final Color fg;
  final Color bg;
  final Color border;
  final IconData icon;
}
