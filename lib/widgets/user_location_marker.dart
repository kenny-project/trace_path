import 'package:flutter/material.dart';

/// 高德地图风格的用户位置标记组件
/// - 红色定位大头针
/// - 内部蓝色衣服人物头像
/// - 顶部"我"字气泡标注
class UserLocationMarker extends StatelessWidget {
  final double pinSize;
  final double avatarSize;
  final bool showLabel;

  const UserLocationMarker({
    super.key,
    this.pinSize = 36,
    this.avatarSize = 18,
    this.showLabel = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 顶部气泡标签
        if (showLabel)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              '我',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFFE53935), // 红色文字
              ),
            ),
          ),
        // 红色大头针
        SizedBox(
          width: pinSize,
          height: pinSize + 10,
          child: CustomPaint(
            painter: _RedPinPainter(),
            child: Center(
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF1E88E5), // 蓝色衣服
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: const Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 红色大头针 CustomPainter
class _RedPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935) // 红色
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    // 顶部圆弧 + 底部尖角：近似高德地图的大头针形状
    final pinPath = Path()
      // 从左侧中点开始，顺时针画
      ..moveTo(0, h * 0.28)
      ..lineTo(0, h * 0.55)
      ..quadraticBezierTo(0, h * 0.82, w * 0.5, h) // 左下弧→底部尖
      ..quadraticBezierTo(w, h * 0.82, w, h * 0.55) // 右下弧
      ..lineTo(w, h * 0.28)
      ..quadraticBezierTo(w, 0, w * 0.5, 0) // 顶部圆弧
      ..quadraticBezierTo(0, 0, 0, h * 0.28) // 回到起点
      ..close();

    // 绘制阴影（向下偏移）
    canvas.save();
    canvas.translate(1.5, 2.5);
    canvas.drawPath(pinPath.shift(const Offset(0, 0)), shadowPaint);
    canvas.restore();

    // 叠加白色高光小圆（视觉层次感）
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.fill;

    // 绘制主体
    canvas.drawPath(pinPath, paint);

    // 顶部内凹效果（小圆叠加）
    canvas.drawCircle(
      Offset(w * 0.5, h * 0.22),
      w * 0.28,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// 普通好友标记（白色气泡 + 红色小头针）
class FriendLocationMarker extends StatelessWidget {
  final String emoji;
  final String? label;
  final double pinSize;
  final double avatarSize;

  const FriendLocationMarker({
    super.key,
    required this.emoji,
    this.label,
    this.pinSize = 36,
    this.avatarSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 气泡标签（可选）
        if (label != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            child: Text(
              label!,
              style: const TextStyle(fontSize: 10, color: Colors.black87),
            ),
          ),
        // 小红色头针
        SizedBox(
          width: pinSize,
          height: pinSize + 6,
          child: CustomPaint(
            painter: _SmallRedPinPainter(),
            child: Center(
              child: Container(
                width: avatarSize,
                height: avatarSize,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.2),
                ),
                child: Text(emoji, style: const TextStyle(fontSize: 12)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 小号红色大头针（好友用）
class _SmallRedPinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE53935)
      ..style = PaintingStyle.fill;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.28)
      ..lineTo(0, h * 0.55)
      ..quadraticBezierTo(0, h * 0.82, w * 0.5, h)
      ..quadraticBezierTo(w, h * 0.82, w, h * 0.55)
      ..lineTo(w, h * 0.28)
      ..quadraticBezierTo(w, 0, w * 0.5, 0)
      ..quadraticBezierTo(0, 0, 0, h * 0.28)
      ..close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
