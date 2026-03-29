import 'package:flutter/material.dart';
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
  late bool _enabled;
  late int _intervalSeconds;
  late bool _powerSaving;
  bool _isLoading = false;
  bool _isServiceRunning = false; // 实际服务运行状态

  @override
  void initState() {
    super.initState();
    _enabled = widget.settingsService.settings.enabled;
    _intervalSeconds = widget.settingsService.settings.intervalSeconds;
    _powerSaving = widget.settingsService.settings.powerSaving;
    _checkServiceRunning();
  }

  Future<void> _checkServiceRunning() async {
    final running = await widget.locationService.checkRunning();
    if (mounted) {
      setState(() {
        _isServiceRunning = running;
        // 开关状态应该完全反映服务运行状态
        _enabled = running;
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
            Center(
              child: Text(
                ws.WidgetStrings.locationSettingsTitle,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 24),
            _buildSwitchTile(
              label: ws.WidgetStrings.enableRealTimeLocation,
              icon: Icons.location_on,
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
            const Divider(height: 24),
            _buildDropdownTile(),
            const SizedBox(height: 16),
            _buildSwitchTile(
              label: ws.WidgetStrings.powerSavingMode,
              icon: Icons.battery_saver,
              value: _powerSaving,
              subtitle: ws.WidgetStrings.powerSavingDesc,
              onChanged: (v) => setState(() => _powerSaving = v),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(ws.WidgetStrings.cancel),
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
                        : Text(ws.WidgetStrings.confirm),
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
              if (_isServiceRunning && value)
                Text(
                  '服务运行中',
                  style: TextStyle(fontSize: 11, color: Colors.green[600]),
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
        Expanded(
          child: Text(ws.WidgetStrings.locationInterval, style: const TextStyle(fontSize: 15)),
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
      // 先更新设置
      await widget.settingsService.update(
        enabled: _enabled,
        intervalSeconds: _intervalSeconds,
        powerSaving: _powerSaving,
      );

      if (_enabled) {
        if (_isServiceRunning) {
          // 服务已在运行，只更新配置参数
          await widget.locationService.updateSettings(
            intervalSeconds: _intervalSeconds,
            powerSaving: _powerSaving,
          );
        } else {
          // 服务未运行，启动服务
          final ok = await widget.locationService.start();
          if (!ok && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(ws.WidgetStrings.locationPermissionDenied),
                backgroundColor: Colors.orange,
              ),
            );
            // 启动失败，关闭开关
            setState(() => _enabled = false);
          }
        }
      } else {
        if (_isServiceRunning) {
          // 服务正在运行，停止服务
          await widget.locationService.stop();
        }
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${ws.WidgetStrings.startFailed}: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
