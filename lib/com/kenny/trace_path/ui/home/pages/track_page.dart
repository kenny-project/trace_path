import 'package:flutter/material.dart';
import 'package:trace_path/constants/colors.dart';
import '../../../services/track_service.dart';
import '../../../services/friend_service.dart';
import '../../../services/background_location_service.dart';
import '../../../models/location_event.dart';
import 'track_map_page.dart';

class TrackPage extends StatefulWidget {
  const TrackPage({super.key});

  @override
  State<TrackPage> createState() => _TrackPageState();
}

class _TrackPageState extends State<TrackPage> {
  final TrackService _trackService = TrackService();
  final FriendService _friendService = FriendService();
  final BackgroundLocationService _locationService = BackgroundLocationService();

  // 当前展开的层级
  String? _expandedPhone;
  String? _expandedYear;
  String? _expandedMonth;

  bool _isLoading = true;
  Map<String, Map<String, Map<String, List<String>>>> _hierarchy = {};

  // 定位订阅
  VoidCallback? _locationUnsubscribe;

  @override
  void initState() {
    super.initState();
    _loadData();
    // 订阅位置更新，收到后刷新轨迹列表
    _locationUnsubscribe = _locationService.subscribe(_onLocationEvent);
  }

  @override
  void dispose() {
    _locationUnsubscribe?.call();
    super.dispose();
  }

  /// 处理位置更新事件
  void _onLocationEvent(LocationEvent event) {
    if (event.type == LocationEventType.locationUpdate) {
      // 有新位置时，延迟刷新轨迹列表（避免频繁刷新）
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loadData();
        }
      });
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final hierarchy = await _trackService.getTrackHierarchy();
    if (mounted) {
      setState(() {
        _hierarchy = hierarchy;
        _isLoading = false;
        // 默认展开第一个人员的列表（当前用户优先）
        if (hierarchy.isNotEmpty && _expandedPhone == null) {
          final selfPhone = _friendService.getSelfPhone();
          final phones = hierarchy.keys.toList();
          phones.sort((a, b) {
            if (a == selfPhone) return -1;
            if (b == selfPhone) return 1;
            return a.compareTo(b);
          });
          _expandedPhone = phones.first;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '轨迹列表',
          style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.black87),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _onRefresh,
              color: AppColors.primary,
              child: _buildContent(),
            ),
    );
  }

  Widget _buildContent() {
    if (_hierarchy.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height - 200,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.route, size: 64, color: Colors.grey[300]),
                  const SizedBox(height: 16),
                  Text(
                    '暂无轨迹数据',
                    style: TextStyle(fontSize: 16, color: Colors.grey[500]),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '下拉刷新试试',
                    style: TextStyle(fontSize: 13, color: Colors.grey[400]),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: _buildHierarchyList(),
    );
  }

  Future<void> _onRefresh() async {
    await _loadData();
  }

  List<Widget> _buildHierarchyList() {
    final widgets = <Widget>[];

    // 按手机号排序（好友优先，自己的号码在前）
    final selfPhone = _friendService.getSelfPhone();
    final sortedPhones = _hierarchy.keys.toList()
      ..sort((a, b) {
        if (a == selfPhone) return -1;
        if (b == selfPhone) return 1;
        return a.compareTo(b);
      });

    for (final phone in sortedPhones) {
      widgets.add(_buildPhoneItem(phone));

      // 年份层级
      if (_expandedPhone == phone) {
        final years = _hierarchy[phone]!.keys.toList()
          ..sort((a, b) => b.compareTo(a));

        for (final year in years) {
          final months = _hierarchy[phone]![year]!.keys.toList()
            ..sort((a, b) => b.compareTo(a));

          // 如果只有一年，直接显示月份/日期（不显示年份项）
          if (years.length == 1) {
            for (final month in months) {
              final days = _hierarchy[phone]![year]![month]!;

              // 如果只有一月，直接显示日期（不显示月份项）
              if (months.length == 1) {
                for (final day in days) {
                  // 显示扁平化的日期: 20230329
                  widgets.add(_buildDayItemFlat(phone, year, month, day));
                }
              } else {
                widgets.add(_buildMonthItem(phone, year, month));

                // 月份展开时显示日期
                if (_expandedMonth == '$phone/$year/$month') {
                  for (final day in days) {
                    widgets.add(_buildDayItem(phone, int.parse(year), int.parse(month), int.parse(day)));
                  }
                }
              }
            }
          } else {
            // 多年份，正常显示年份层级
            widgets.add(_buildYearItem(phone, year));

            if (_expandedYear == '$phone/$year') {
              for (final month in months) {
                widgets.add(_buildMonthItem(phone, year, month));

                if (_expandedMonth == '$phone/$year/$month') {
                  final days = _hierarchy[phone]![year]![month]!;
                  for (final day in days) {
                    widgets.add(_buildDayItem(phone, int.parse(year), int.parse(month), int.parse(day)));
                  }
                }
              }
            }
          }
        }
      }
    }

    return widgets;
  }

  /// 手机号层级
  Widget _buildPhoneItem(String phone) {
    final friend = _friendService.getFriend(phone);
    final name = friend?.name ?? phone;
    final emoji = friend?.emoji ?? '📱';
    final isExpanded = _expandedPhone == phone;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary, width: 2),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _expandedPhone = isExpanded ? null : phone;
            _expandedYear = null;
            _expandedMonth = null;
          });
        },
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 24))),
        ),
        title: Text(
          name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
        subtitle: Text(
          phone,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
        trailing: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: AppColors.primary,
        ),
      ),
    );
  }

  /// 年份层级
  Widget _buildYearItem(String phone, String year) {
    final isExpanded = _expandedYear == '$phone/$year';
    final monthCount = _hierarchy[phone]![year]!.keys.length;

    return Container(
      margin: const EdgeInsets.only(left: 20, top: 4),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _expandedYear = isExpanded ? null : '$phone/$year';
            _expandedMonth = null;
          });
        },
        dense: true,
        leading: const Icon(Icons.calendar_today, size: 20, color: AppColors.primary),
        title: Text(
          '$year 年',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text('$monthCount 个月', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        trailing: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.grey,
        ),
      ),
    );
  }

  /// 月份层级
  Widget _buildMonthItem(String phone, String year, String month) {
    final isExpanded = _expandedMonth == '$phone/$year/$month';
    final days = _hierarchy[phone]![year]![month]!;
    final monthName = _getMonthName(int.parse(month));

    return Container(
      margin: const EdgeInsets.only(left: 40, top: 2),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        onTap: () {
          setState(() {
            _expandedMonth = isExpanded ? null : '$phone/$year/$month';
          });
        },
        dense: true,
        leading: const Icon(Icons.event, size: 18, color: AppColors.primary),
        title: Text(
          '$monthName',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Text('${days.length} 天', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        trailing: Icon(
          isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
          color: Colors.grey,
          size: 20,
        ),
      ),
    );
  }

  /// 日期层级
  Widget _buildDayItem(String phone, int year, int month, int day) {
    final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final dayName = _getDayName(year, month, day);
    
    // 判断是否是今天/昨天/前天
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(year, month, day);
    final difference = today.difference(targetDate).inDays;
    final isRecent = difference >= 0 && difference <= 2;
    
    // 显示内容
    String displayText;
    if (isRecent) {
      // 今天/昨天/前天：显示时分秒
      displayText = dayName;
    } else {
      displayText = '$dayName ($dateStr)';
    }

    return GestureDetector(
      onTap: () => _openTrackMap(phone, year, month, day),
      child: Container(
        margin: const EdgeInsets.only(left: 60, top: 1),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Icon(Icons.access_time, size: 16, color: Colors.grey),
            ),
            Expanded(
              child: FutureBuilder<DateTime?>(
                future: isRecent ? _trackService.getFileModifyTime(phone, year, month, day) : Future.value(null),
                builder: (context, snapshot) {
                  String text = displayText;
                  if (isRecent && snapshot.hasData) {
                    final time = snapshot.data!;
                    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                    text = '$displayText $timeStr';
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
              onPressed: () => _handleDelete(phone, year, month, day),
            ),
          ],
        ),
      ),
    );
  }

  /// 扁平化日期显示（如20230329）
  Widget _buildDayItemFlat(String phone, String year, String month, String day) {
    final dateStr = '$year-${month.padLeft(2, '0')}-${day.padLeft(2, '0')}';
    final yearInt = int.parse(year);
    final monthInt = int.parse(month);
    final dayInt = int.parse(day);
    final dayName = _getDayName(yearInt, monthInt, dayInt);
    
    // 判断是否是今天/昨天/前天
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(yearInt, monthInt, dayInt);
    final difference = today.difference(targetDate).inDays;
    final isRecent = difference >= 0 && difference <= 2;
    
    // 显示内容
    String displayText;
    if (isRecent) {
      // 今天/昨天/前天：显示时分秒
      displayText = dayName;
    } else {
      displayText = '$dayName ($dateStr)';
    }

    return GestureDetector(
      onTap: () => _openTrackMap(phone, yearInt, monthInt, dayInt),
      child: Container(
        margin: const EdgeInsets.only(left: 20, top: 2),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 16),
              child: Icon(Icons.access_time, size: 16, color: AppColors.primary),
            ),
            Expanded(
              child: FutureBuilder<DateTime?>(
                future: isRecent ? _trackService.getFileModifyTime(phone, yearInt, monthInt, dayInt) : Future.value(null),
                builder: (context, snapshot) {
                  String text = displayText;
                  if (isRecent && snapshot.hasData) {
                    final time = snapshot.data!;
                    final timeStr = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
                    text = '$displayText $timeStr';
                  }
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      text,
                      style: const TextStyle(fontSize: 13, color: AppColors.primary),
                    ),
                  );
                },
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.grey),
              onPressed: () => _handleDelete(phone, yearInt, monthInt, dayInt),
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthName(int month) {
    const months = ['一月', '二月', '三月', '四月', '五月', '六月', '七月', '八月', '九月', '十月', '十一月', '十二月'];
    return months[month - 1];
  }

  String _getDayName(int year, int month, int day) {
    final date = DateTime(year, month, day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final targetDate = DateTime(year, month, day);
    
    final difference = today.difference(targetDate).inDays;
    
    if (difference == 0) {
      return '今天';
    } else if (difference == 1) {
      return '昨天';
    } else if (difference == 2) {
      return '前天';
    } else {
      const weekdays = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      return weekdays[date.weekday - 1];
    }
  }

  Future<void> _openTrackMap(String phone, int year, int month, int day) async {
    final friend = _friendService.getFriend(phone);
    final name = friend?.name ?? phone;
    final emoji = friend?.emoji ?? '📱';

    final points = await _trackService.readDayTrack(phone, year, month, day);
    if (!mounted) return;

    if (points.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该日期暂无轨迹数据')),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackMapPage(
          phoneNumber: phone,
          name: name,
          emoji: emoji,
          year: year,
          month: month,
          day: day,
          points: points,
        ),
      ),
    );
  }

  /// 处理删除
  Future<void> _handleDelete(String phone, int year, int month, int day) async {
    final confirmed = await _confirmDelete(phone, year, month, day);
    if (confirmed) {
      await _deleteTrackFile(phone, year, month, day);
    }
  }

  /// 确认删除对话框
  Future<bool> _confirmDelete(String phone, int year, int month, int day) async {
    final dateStr = '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除确认'),
        content: Text('确定要删除 $dateStr 的轨迹记录吗？\n此操作不可恢复。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  /// 删除轨迹文件
  Future<void> _deleteTrackFile(String phone, int year, int month, int day) async {
    try {
      final success = await _trackService.deleteDayTrack(phone, year, month, day);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除轨迹记录')),
        );
      }
      // 刷新列表
      await _loadData();
    } catch (e) {
      print('[TrackPage] 删除失败: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败: $e')),
      );
    }
  }
}
