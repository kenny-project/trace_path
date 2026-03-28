import 'package:flutter/material.dart';
import '../services/location_settings_service.dart';
import '../services/background_location_service.dart';

/// 实时定位设置弹窗
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
  late bool _enabled;
  late int _intervalSeconds;
  late bool _powerSaving;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _enabled = widget.settingsService.settings.enabled;
    _intervalSeconds = widget.settingsService.settings.intervalSeconds;
    _powerSaving = widget.settingsService.settings.powerSaving;
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
            // 标题
            const Center(
              child: Text(
                '实时定位设置',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),

            // 开启实时定位
            _buildSwitchTile(
              label: '开启实时定位',
              icon: Icons.location_on,
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),

            const Divider(height: 24),

            // 定位频率
            _buildDropdownTile(),

            const SizedBox(height: 16),

            // 省电模式
            _buildSwitchTile(
              label: '省电模式',
              icon: Icons.battery_saver,
              value: _powerSaving,
              subtitle: '静止时自动降低定位频率',
              onChanged: (v) => setState(() => _powerSaving = v),
            ),

            const SizedBox(height: 24),

            // 按钮行
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _onConfirm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF50D2B2),
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
                        : const Text('确认'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String label,
    required IconData icon,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? subtitle,
  }) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF50D2B2).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: const Color(0xFF50D2B2), size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 15)),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
            ],
          ),
        ),
        Switch(
          value: value,
          activeColor: const Color(0xFF50D2B2),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildDropdownTile() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFF50D2B2).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.timer, color: Color(0xFF50D2B2), size: 20),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text('定位频率', style: TextStyle(fontSize: 15)),
        ),
        DropdownButton<int>(
          value: _intervalSeconds,
          underline: const SizedBox(),
          items: LocationInterval.options.map((opt) {
            return DropdownMenuItem(
              value: opt.seconds,
              child: Text(opt.label, style: const TextStyle(fontSize: 14)),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) setState(() => _intervalSeconds = v);
          },
        ),
      ],
    );
  }

  Future<void> _onConfirm() async {
    setState(() => _isLoading = true);

    try {
      // 保存设置
      await widget.settingsService.update(
        enabled: _enabled,
        intervalSeconds: _intervalSeconds,
        powerSaving: _powerSaving,
      );

      // 启动或停止服务
      if (_enabled) {
        final ok = await widget.locationService.start();
        if (!ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('定位权限被拒绝，请在设置中开启'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        await widget.locationService.stop();
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('启动失败: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
