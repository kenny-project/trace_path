import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../services/track_service.dart';

/// 轨迹地图页面
class TrackMapPage extends StatefulWidget {
  final String phoneNumber;
  final String name;
  final String emoji;
  final int year;
  final int month;
  final int day;
  final List<TrackPoint> points;

  const TrackMapPage({
    super.key,
    required this.phoneNumber,
    required this.name,
    required this.emoji,
    required this.year,
    required this.month,
    required this.day,
    required this.points,
  });

  @override
  State<TrackMapPage> createState() => _TrackMapPageState();
}

class _TrackMapPageState extends State<TrackMapPage> {
  final MapController _mapController = MapController();

  late List<LatLng> _polylinePoints;
  late LatLng _center;

  @override
  void initState() {
    super.initState();
    _initPolyline();
  }

  void _initPolyline() {
    _polylinePoints = widget.points.map((p) => p.toLatLng()).toList();

    if (_polylinePoints.isNotEmpty) {
      double sumLat = 0;
      double sumLng = 0;
      for (final point in _polylinePoints) {
        sumLat += point.latitude;
        sumLng += point.longitude;
      }
      _center = LatLng(sumLat / _polylinePoints.length, sumLng / _polylinePoints.length);
    } else {
      _center = const LatLng(39.908823, 116.397470);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.emoji, style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 8),
            Text(
              '${widget.name} ${widget.year}-${widget.month.toString().padLeft(2, '0')}-${widget.day.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ],
        ),
        centerTitle: true,
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _center,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://webrd0{s}.is.autonavi.com/appmaptile?lang=zh_cn&size=1&scale=1&style=8&x={x}&y={y}&z={z}',
                subdomains: const ['1', '2', '3', '4'],
                userAgentPackageName: 'com.example.trace_path',
              ),
              if (_polylinePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _polylinePoints,
                      color: const Color(0xFF2D7AF6),
                      strokeWidth: 4,
                    ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: _buildBottomInfo(),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomInfo() {
    if (widget.points.isEmpty) return const SizedBox.shrink();

    final firstPoint = widget.points.first;
    final lastPoint = widget.points.last;

    double totalDistance = 0;
    for (int i = 1; i < widget.points.length; i++) {
      final prev = widget.points[i - 1];
      final curr = widget.points[i];
      const distance = Distance();
      totalDistance += distance.as(LengthUnit.Meter, prev.toLatLng(), curr.toLatLng());
    }

    final distanceStr = totalDistance > 1000
        ? '${(totalDistance / 1000).toStringAsFixed(2)} km'
        : '${totalDistance.toStringAsFixed(0)} m';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildInfoItem('起点时间', _formatTime(firstPoint.timestamp)),
          _buildInfoItem('终点时间', _formatTime(lastPoint.timestamp)),
          _buildInfoItem('总距离', distanceStr),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    if (widget.points.isEmpty) return [];

    final markers = <Marker>[];

    markers.add(
      Marker(
        point: widget.points.first.toLatLng(),
        width: 30,
        height: 30,
        child: Container(
          decoration: const BoxDecoration(
            color: Color(0xFF4CAF50),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.play_arrow, color: Colors.white, size: 18),
        ),
      ),
    );

    if (widget.points.length > 1) {
      markers.add(
        Marker(
          point: widget.points.last.toLatLng(),
          width: 30,
          height: 30,
          child: Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFF5722),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.stop, color: Colors.white, size: 18),
          ),
        ),
      );
    }

    return markers;
  }

  String _formatTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
  }
}
