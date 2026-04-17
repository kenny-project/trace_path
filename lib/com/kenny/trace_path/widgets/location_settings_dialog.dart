import 'package:flutter/material.dart';
import 'package:trace_path/constants/colors.dart';
import '../services/location_settings_service.dart';
import '../services/background_location_service.dart';
import 'package:trace_path/constants/strings.dart';
import 'package:trace_path/constants/widget_strings.dart' as ws;

class LocationSettingsDialog extends StatefulWidget {
  final LocationSettingsService settingsService;
  final BackgroundLocationService locationService;

  const LocationSettingsDialog({
    super.key,
    required this.settingsService,
    required this.locationService,
  });

  @override
  State<LocationSettingsDialog> createState() => _LocationSettingsDialogState();
}

class _LocationSettingsDialogState extends State<LocationSettingsDialog> {
  late bool _powerSaving;
  bool _isLoading = false;
  bool _isServiceRunning = false; // 实际服务运行状态

  @override
  void initState() {
    super.initState();
    _powerSaving = widget.settingsService.settings.powerSaving;
    _checkServiceRunning();
  }

  Future<void> _checkServiceRunning() async {
    final running = await widget.locationService.checkRunning();
    print('[LocationSettingsDialog] _checkServiceRunning: running=$running');
    if (mounted) {
      setState(() {
        _isServiceRunning = running;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题栏
            Row(
              children: [
                const Icon(Icons.location_on, color: AppColors.primary, size: 24),
                const SizedBox(width: 8),
                const Text(
                  ws.WidgetStrings.locationSettingsTitle,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (_isServiceRunning)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.green[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.green[200]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle, color: Colors.green[600], size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '运行中',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 20),

            // 服务开关（主要操作）
            _buildServiceToggle(),
            const SizedBox(height: 16),

            // 省电模式开关（启用后可见）
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child: _isServiceRunning ? _buildPowerSavingToggle() : const SizedBox.shrink(),
            ),

            // 动态间隔说明（启用后显示）
            if (_isServiceRunning) ...[
              const SizedBox(height: 16),
              _buildDynamicIntervalInfo(),
            ],

            const SizedBox(height: 20),
            const Divider(height: 1),
            const SizedBox(height: 16),

            // 按钮行
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    child: Text(ws.WidgetStrings.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_isServiceRunning ? '保存' : '启动定位'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 服务开关
  Widget _buildServiceToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isServiceRunning ? AppColors.primary.withValues(alpha: 0.08) : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isServiceRunning ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey[300]!,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _isServiceRunning ? AppColors.primary : Colors.grey[400],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _isServiceRunning ? Icons.location_on : Icons.location_off,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ws.WidgetStrings.enableRealTimeLocation,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: _isServiceRunning ? Colors.black87 : Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _isServiceRunning
                      ? '实时追踪您的位置变化'
                      : '点击按钮启动定位服务',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Switch(
            value: _isServiceRunning,
            activeColor: AppColors.primary,
            onChanged: null, // 禁用滑动，通过按钮操作
          ),
        ],
      ),
    );
  }

  /// 省电模式开关
  Widget _buildPowerSavingToggle() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: _powerSaving ? Colors.green[50] : Colors.orange[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _powerSaving ? Icons.battery_saver : Icons.gps_fixed,
              color: _powerSaving ? Colors.green : Colors.orange,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ws.WidgetStrings.powerSavingMode,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  _powerSaving ? '低功耗模式，定位间隔加倍' : '高性能模式，定位更精确',
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
          Switch(
            value: _powerSaving,
            activeColor: Colors.green,
            onChanged: (v) => setState(() => _powerSaving = v),
          ),
        ],
      ),
    );
  }

  /// 动态间隔说明
  Widget _buildDynamicIntervalInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[100]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, color: Colors.blue[600], size: 18),
              const SizedBox(width: 8),
              Text(
                '智能动态间隔',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '定位间隔会根据您的移动速度自动调整：',
            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
          ),
          const SizedBox(height: 6),
          _buildIntervalRow(Icons.directions_walk, '静止/步行', '< 60s'),
          _buildIntervalRow(Icons.directions_bike, '骑行', '15s'),
          _buildIntervalRow(Icons.directions_car, '驾车', '10s'),
        ],
      ),
    );
  }

  Widget _buildIntervalRow(IconData icon, String label, String interval) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
          const Spacer(),
          Text(
            interval,
            style: TextStyle(fontSize: 12, color: Colors.blue[600], fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Future<void> _onConfirm() async {
    setState(() => _isLoading = true);

    try {
      if (_isServiceRunning) {
        // 更新设置并保持服务运行
        await widget.settingsService.update(
          enabled: true,
          powerSaving: _powerSaving,
        );

        await widget.locationService.updateSettings(
          powerSaving: _powerSaving,
        );
      } else {
        // 停止服务
        await widget.settingsService.update(enabled: false);
        await widget.locationService.stop();
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('操作失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
