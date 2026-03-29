import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/location_strings.dart' as ls;
import '../../../services/background_location_service.dart';
import '../../../services/friend_service.dart';
import '../../../models/friend_model.dart';

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  final TextEditingController _searchController = TextEditingController();
  final MapController _mapController = MapController();
  final BackgroundLocationService _locationService =
      BackgroundLocationService();
  final FriendService _friendService = FriendService();

  // 当前位置
  double _myLat = 39.908823;
  double _myLng = 116.397470;
  bool _isLoadingLocation = true;

  // UI状态
  bool _showSearchBar = true; // 搜索栏默认显示
  bool _isFriendsListExpanded = true; // 好友列表默认展开
  static const int _maxVisibleFriends = 1; // 折叠时显示1个好友

  // 地图状态
  double _currentZoom = 14;
  double _currentRotation = 0;

  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
    _friendService.init();
  }

  Future<void> _loadCurrentLocation() async {
    final position = await _locationService.getCurrentPosition();
    if (position != null && mounted) {
      setState(() {
        _myLat = position.latitude;
        _myLng = position.longitude;
        _isLoadingLocation = false;
      });
      _mapController.move(LatLng(_myLat, _myLng), 14);

      // 获取地址并更新好友位置
      final address = await _locationService.getAddressFromLatLng(_myLat, _myLng);
      await _friendService.updateFriendLocation('18511698488', _myLat, _myLng, address: address);
    } else {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _toggleSearchBar() {
    setState(() {
      _showSearchBar = !_showSearchBar;
    });
  }

  void _toggleFriendsList() {
    setState(() {
      _isFriendsListExpanded = !_isFriendsListExpanded;
    });
  }

  Future<void> _addFriend() async {
    final phone = _searchController.text.trim();
    if (phone.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入手机号')));
      return;
    }

    final friend = Friend(
      phoneNumber: phone,
      name: '好友$phone',
      emoji: '👤',
      lat: _myLat,
      lng: _myLng,
      lastUpdateTime: DateTime.now(),
    );

    final success = await _friendService.addFriend(friend);
    if (success) {
      _searchController.clear();
      setState(() {
        _showSearchBar = false;
      });
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已添加好友 $phone')));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('好友 $phone 已存在')));
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    // 收起键盘
    FocusScope.of(context).unfocus();
  }

  /// 放大
  void _zoomIn() {
    if (_currentZoom < 18) {
      _currentZoom += 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
      setState(() {});
    }
  }

  /// 缩小
  void _zoomOut() {
    if (_currentZoom > 3) {
      _currentZoom -= 1;
      _mapController.move(_mapController.camera.center, _currentZoom);
      setState(() {});
    }
  }

  /// 复位地图（归位到正北方向，zoom 14）
  void _resetMapView() {
    _mapController.move(LatLng(_myLat, _myLng), 14);
    _mapController.rotate(0);
    setState(() {
      _currentZoom = 14;
      _currentRotation = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // 地图
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: LatLng(_myLat, _myLng),
                  initialZoom: 14,
                  minZoom: 3,
                  maxZoom: 18, // 最大18级，防止无底图
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.all,
                  ),
                  onTap: _onMapTap,
                  onPositionChanged: (position, hasGesture) {
                    if (hasGesture) {
                      if (position.zoom != null) {
                        _currentZoom = position.zoom!;
                      }
                      _currentRotation = _mapController.camera.rotation;
                      setState(() {});
                    }
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                    subdomains: const ['1', '2', '3', '4'],
                    userAgentPackageName: 'com.kenny.trace_path',
                    maxZoom: 18, // 高德底图最大18级
                  ),
                  MarkerLayer(markers: _buildMarkers()),
                ],
              ),
              // 指南针（左侧，搜索栏下方）
              Positioned(left: 16, top: 130, child: _buildCompass()),
              // 缩放按钮 + 定位按钮（右侧，好友列表上方）
              Positioned(
                right: 16,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildLocationButton(),
                    const SizedBox(height: 8),
                    _buildZoomControls(),
                  ],
                ),
              ),
              // 比例尺（左下角）
              Positioned(left: 16, bottom: 16, child: _buildScaleBar()),
              // 搜索栏（浮动在地图上）
              if (_showSearchBar)
                Positioned(
                  left: 16,
                  right: 16,
                  top: 50,
                  child: _buildSearchBar(),
                ),
              // 高德版权信息（透明背景，浮在地图上）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _buildAmapAttribution(),
              ),
            ],
          ),
        ),
        // 好友列表（可展开/折叠）
        _buildFriendsListSection(),
      ],
    );
  }

  /// 指南针组件
  Widget _buildCompass() {
    return GestureDetector(
      onTap: _resetMapView,
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
        child: Transform.rotate(
          angle: _currentRotation * 3.14159 / 180, // 转换为弧度
          child: const Icon(Icons.navigation, color: Color(0xFF2D7AF6), size: 28),
        ),
      ),
    );
  }

  /// 定位按钮
  Widget _buildLocationButton() {
    return GestureDetector(
      onTap: () async {
        // 刷新当前位置
        setState(() => _isLoadingLocation = true);
        final position = await _locationService.getCurrentPosition();
        if (position != null && mounted) {
          setState(() {
            _myLat = position.latitude;
            _myLng = position.longitude;
            _isLoadingLocation = false;
          });
          _mapController.move(LatLng(_myLat, _myLng), 14);
          // 获取地址并更新
          final address = await _locationService.getAddressFromLatLng(_myLat, _myLng);
          await _friendService.updateFriendLocation('18511698488', _myLat, _myLng, address: address);
          setState(() {}); // 刷新UI显示新地址
        } else {
          if (mounted) {
            setState(() => _isLoadingLocation = false);
          }
        }
      },
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
        child: _isLoadingLocation
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(
                Icons.my_location,
          color: Color(0xFF2D7AF6),
          size: 24,
        ),
      ),
    );
  }

  /// 缩放控制按钮
  Widget _buildZoomControls() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 放大按钮
          GestureDetector(
            onTap: _zoomIn,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1),
                ),
              ),
              child: const Icon(Icons.add, size: 22, color: Colors.black87),
            ),
          ),
          // 缩小按钮
          GestureDetector(
            onTap: _zoomOut,
            child: Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              child: const Icon(Icons.remove, size: 22, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// 比例尺
  Widget _buildScaleBar() {
    // 根据当前zoom计算比例尺
    String distance;
    if (_currentZoom >= 16) {
      distance = '50m';
    } else if (_currentZoom >= 14) {
      distance = '200m';
    } else if (_currentZoom >= 12) {
      distance = '500m';
    } else if (_currentZoom >= 10) {
      distance = '1km';
    } else if (_currentZoom >= 8) {
      distance = '2km';
    } else if (_currentZoom >= 6) {
      distance = '5km';
    } else {
      distance = '10km';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 4),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            distance,
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            width: 40,
            height: 3,
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(1),
            ),
          ),
          const SizedBox(height: 2),
          Container(width: 40, height: 1, color: Colors.white),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.search, color: Colors.grey),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                hintText: '查找TA的手机号',
                hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: _addFriend,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2D7AF6), // 品牌蓝色
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              elevation: 0,
            ),
            child: const Text('查找好友', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildFriendBubble() {
    final friends = _friendService.friends;
    if (friends.isEmpty) return const SizedBox.shrink();

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
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(friends.first.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 4),
          Text(
            friends.first.name,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final friends = _friendService.friends;
    return friends.map((friend) {
      final lat = friend.lat ?? _myLat;
      final lng = friend.lng ?? _myLng;
      return Marker(
        point: LatLng(lat, lng),
        width: 40,
        height: 50,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: friend.phoneNumber == '18511698488'
                    ? const Color(0xFFFFD700)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 3,
                  ),
                ],
              ),
              child: Text(friend.emoji, style: const TextStyle(fontSize: 16)),
            ),
            const Icon(Icons.location_on, color: Colors.red, size: 24),
          ],
        ),
      );
    }).toList();
  }

  Widget _buildFriendsListSection() {
    final friends = _friendService.friends;

    // 限制最多显示的数量
    const maxItems = 4;
    final actualDisplayCount = _isFriendsListExpanded
        ? friends.length.clamp(0, maxItems)
        : 0;

    // 动态计算高度（标题栏始终显示）
    const headerHeight = 48.0; // 标题栏高度
    const itemHeight = 100.0; // 每个好友项的高度（100足够显示地址等信息）
    final totalHeight = headerHeight + (actualDisplayCount * itemHeight);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      height: totalHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(20),
          topRight: Radius.circular(20),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 标题栏（可点击展开/折叠）- 始终显示
          GestureDetector(
            onTap: _toggleFriendsList,
            child: Container(
              height: headerHeight,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    '我的好友 (${friends.length})',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _isFriendsListExpanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_up,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          // 好友列表（折叠时隐藏）
          if (_isFriendsListExpanded)
            SizedBox(
              height: actualDisplayCount * itemHeight,
              child: ListView.builder(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: actualDisplayCount,
                itemBuilder: (context, index) {
                  return _buildFriendItem(friends[index]);
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFriendItem(Friend friend) {
    // 格式化时间显示
    String timeStr = '';
    if (friend.lastUpdateTime != null) {
      final dt = friend.lastUpdateTime!;
      timeStr = '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF0F0F0), width: 1)),
      ),
      child: Row(
        children: [
          // 头像
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xFF2D7AF6), width: 2),
            ),
            child: Center(
              child: Text(friend.emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
          const SizedBox(width: 12),
          // 详细信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 名字 + 时间
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        friend.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF333333),
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (timeStr.isNotEmpty)
                      Text(
                        timeStr,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF999999),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                // 地址
                if (friend.address != null)
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 14,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          friend.address!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF666666),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  )
                else if (friend.lat != null && friend.lng != null)
                  Text(
                    '定位: ${friend.lat!.toStringAsFixed(6)}, ${friend.lng!.toStringAsFixed(6)}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF999999),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 轨迹按钮
          OutlinedButton(
            onPressed: () {
              if (friend.lat != null && friend.lng != null) {
                _mapController.move(LatLng(friend.lat!, friend.lng!), 14);
              }
            },
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF2D7AF6),
              side: const BorderSide(color: Color(0xFF2D7AF6), width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            ),
            child: const Text('轨迹', style: TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildAmapAttribution() {
    // 透明背景，显示深色文字
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: const Color(0xFF02C1E0),
              borderRadius: BorderRadius.circular(3),
            ),
            child: const Icon(Icons.navigation, size: 9, color: Colors.white),
          ),
          const SizedBox(width: 4),
          Text(
            ls.LocationStrings.amapAttr,
            style: const TextStyle(fontSize: 10, color: Colors.black54),
          ),
          const SizedBox(width: 8),
          Text(
            ls.LocationStrings.amapCopyright,
            style: const TextStyle(fontSize: 9, color: Colors.black38),
          ),
        ],
      ),
    );
  }
}
