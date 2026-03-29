import 'package:flutter/material.dart';
import 'package:trace_path/constants/location_strings.dart' as ls;
import 'package:trace_path/constants/colors.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int _currentIndex = 0;
  final TextEditingController _searchController = TextEditingController();

  final MapController _mapController = MapController();

  // 模拟好友数据
  final List<Map<String, dynamic>> _friends = [
    {
      'name': '我自己',
      'avatar': '🐤',
      'time': '17:21',
      'date': '2026-03-28',
      'address': '北京市朝阳区常营中路179号靠近富力阳光美园',
      'lat': 39.956,
      'lng': 116.618,
    },
  ];

  // 倒计时
  int _countdownSeconds = 13 * 3600 + 53 * 60 + 55;

  @override
  void initState() {
    super.initState();
    _startCountdown();
  }

  void _startCountdown() {
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      setState(() {
        if (_countdownSeconds > 0) _countdownSeconds--;
      });
      return _countdownSeconds > 0;
    });
  }

  String _formatCountdown(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    return '${h.toString().padLeft(2, '0')} : ${m.toString().padLeft(2, '0')} : ${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // ===== 顶部搜索区域 =====
            _buildSearchBar(),

            // ===== 地图区域 =====
            Expanded(
              child: Stack(
                children: [
                  // 地图
                  FlutterMap(
                    mapController: _mapController,
                    options: const MapOptions(
                      initialCenter: LatLng(39.908823, 116.397470),
                      initialZoom: 14,
                    ),
                    children: [
                      // 高德矢量地图瓦片
                      TileLayer(
                        urlTemplate:
                            'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                        subdomains: const ['1', '2', '3', '4'],
                        userAgentPackageName: 'com.kenny.trace_path',
                      ),
                      // 覆盖物层
                      MarkerLayer(markers: _buildMarkers()),
                    ],
                  ),

                  // 好友示例气泡
                  Positioned(left: 12, top: 12, child: _buildFriendBubble()),

                  // 地图右下角控制按钮
                  Positioned(
                    right: 16,
                    bottom: 80,
                    child: Column(
                      children: [
                        _buildMapButton(Icons.add, ls.LocationStrings.addFriend, () {}),
                        const SizedBox(height: 8),
                        _buildMapButton(Icons.my_location, '', () {
                          _mapController.move(
                            const LatLng(39.956, 116.618),
                            14,
                          );
                        }),
                      ],
                    ),
                  ),

                  // 限时优惠横幅
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _buildPromoBanner(),
                  ),
                ],
              ),
            ),

            // ===== 好友列表区域 =====
            _buildFriendsList(),

            // ===== 高德地图版权 =====
            _buildAmapAttribution(),

            // ===== 底部导航 =====
            _buildBottomNav(),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(20),
              ),
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: '请输入对方手机号码',
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                  prefixIcon: Icon(Icons.search, color: Colors.grey),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            height: 40,
            child: ElevatedButton(
              onPressed: () {},
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              child: const Text(ls.LocationStrings.addFriend, style: TextStyle(fontSize: 13)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendBubble() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('👩', style: TextStyle(fontSize: 18)),
          SizedBox(width: 4),
          Text('好友示例', style: TextStyle(fontSize: 12, color: Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildMapButton(IconData icon, String label, VoidCallback onPressed) {
    if (label.isEmpty) {
      // 定位按钮 - 白色圆形
      return GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 6,
              ),
            ],
          ),
          child: Icon(icon, color: Colors.black87, size: 22),
        ),
      );
    }
    // add friend button - green circle
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 7),
            ),
          ],
        ),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return [
      // 好友标记
      Marker(
        point: const LatLng(39.908, 116.396),
        width: 40,
        height: 50,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: const Text('👩', style: TextStyle(fontSize: 18)),
            ),
            const Icon(Icons.location_on, color: Colors.blue, size: 24),
          ],
        ),
      ),
      // 自己的位置
      Marker(
        point: const LatLng(39.956, 116.618),
        width: 40,
        height: 50,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.vipGold,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: const Text('🐤 我', style: TextStyle(fontSize: 12)),
            ),
            const Icon(Icons.location_on, color: Colors.red, size: 24),
          ],
        ),
      ),
    ];
  }

  Widget _buildPromoBanner() {
    return Container(
      height: 60,
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.deepBlue1, AppColors.deepBlue2],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          // 优惠券图标
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.amber[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Text('🎟️', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 10),
          // 文字信息
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '您有一个未支付订单的专属优惠券-¥240',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      _formatCountdown(_countdownSeconds),
                      style: const TextStyle(
                        color: AppColors.vipGold,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      '限时特惠',
                      style: TextStyle(color: AppColors.lightRed, fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 去使用按钮
          GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.only(right: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Text(
                '去使用',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFriendsList() {
    return Container(
      color: Colors.grey[50],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              '我的好友 (${_friends.length})',
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ),
          ...List.generate(
            _friends.length,
            (i) => _buildFriendItem(_friends[i]),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _buildFriendItem(Map<String, dynamic> friend) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          // 头像
          Text(friend['avatar'], style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 10),
          // 信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend['name'],
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.access_time, size: 12, color: Colors.grey),
                    const SizedBox(width: 2),
                    Text(
                      '${friend['date']} ${friend['time']}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 12, color: Colors.grey),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Text(
                        friend['address'],
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 历史轨迹按钮
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            child: const Text('历史轨迹', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  Widget _buildAmapAttribution() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: Colors.grey[100],
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: AppColors.amapBlue,
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(Icons.navigation, size: 10, color: Colors.white),
          ),
          const SizedBox(width: 4),
          const Text(
            '高德地图',
            style: TextStyle(fontSize: 10, color: Colors.grey),
          ),
          const SizedBox(width: 4),
          const Text(
            '© 高德软件 | AutoNavi',
            style: TextStyle(fontSize: 9, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNav() {
    final tabs = [
      {'icon': Icons.location_on, 'label': '定位'},
      {'icon': Icons.route, 'label': '轨迹'},
      {'icon': Icons.shield, 'label': '守护'},
      {'icon': Icons.person, 'label': '我的'},
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isActive = i == _currentIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _currentIndex = i),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tabs[i]['icon'] as IconData,
                      color: isActive ? AppColors.primary : Colors.grey,
                      size: 24,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      tabs[i]['label'] as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: isActive ? AppColors.primary : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
