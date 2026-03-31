import 'dart:typed_data';

/// 轨迹点消息（Protobuf 风格二进制编码）
class TrackPointMessage {
  final int timestampMs;
  final double latitude;
  final double longitude;
  final double altitude;
  final double speed;
  final double accuracy;

  TrackPointMessage({
    required this.timestampMs,
    required this.latitude,
    required this.longitude,
    this.altitude = 0,
    this.speed = 0,
    this.accuracy = 0,
  });

  /// 从 Position 创建
  factory TrackPointMessage.fromPosition({
    required int timestampMs,
    required double latitude,
    required double longitude,
    double altitude = 0,
    double speed = 0,
    double accuracy = 0,
  }) {
    return TrackPointMessage(
      timestampMs: timestampMs,
      latitude: latitude,
      longitude: longitude,
      altitude: altitude,
      speed: speed,
      accuracy: accuracy,
    );
  }

  /// 编码为二进制（Protobuf 风格）
  /// 格式: timestamp_ms(i64) + latitude(double) + longitude(double) + altitude(float) + speed(float) + accuracy(float)
  Uint8List encode() {
    final buffer = ByteData(44); // 8+8+8+4+4+4+4(padding) = 44 bytes
    int offset = 0;
    
    // timestamp_ms: int64 (varint)
    offset += _writeVarint(buffer, offset, timestampMs);
    
    // latitude: double (fixed64)
    buffer.setFloat64(offset, latitude, Endian.little);
    offset += 8;
    
    // longitude: double (fixed64)
    buffer.setFloat64(offset, longitude, Endian.little);
    offset += 8;
    
    // altitude: float (fixed32)
    buffer.setFloat32(offset, altitude, Endian.little);
    offset += 4;
    
    // speed: float (fixed32)
    buffer.setFloat32(offset, speed, Endian.little);
    offset += 4;
    
    // accuracy: float (fixed32)
    buffer.setFloat32(offset, accuracy, Endian.little);
    
    return buffer.buffer.asUint8List();
  }

  /// 解码从二进制
  static TrackPointMessage? decode(Uint8List data, int offset) {
    try {
      final buffer = ByteData.sublistView(data, offset);
      int pos = 0;
      
      // timestamp_ms: varint
      final timestampResult = _readVarint(data, offset);
      if (timestampResult == null) return null;
      pos += timestampResult.bytesRead;
      final timestampMs = timestampResult.value;
      
      // latitude: double
      final latitude = buffer.getFloat64(pos, Endian.little);
      pos += 8;
      
      // longitude: double
      final longitude = buffer.getFloat64(pos, Endian.little);
      pos += 8;
      
      // altitude: float
      final altitude = buffer.getFloat32(pos, Endian.little);
      pos += 4;
      
      // speed: float
      final speed = buffer.getFloat32(pos, Endian.little);
      pos += 4;
      
      // accuracy: float
      final accuracy = buffer.getFloat32(pos, Endian.little);
      
      return TrackPointMessage(
        timestampMs: timestampMs,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        accuracy: accuracy,
      );
    } catch (e) {
      return null;
    }
  }
  
  int get encodedSize => 44; // 固定大小
}

/// Varint 编码/解码工具
int _writeVarint(ByteData buffer, int offset, int value) {
  int pos = 0;
  while (value > 0x7f) {
    buffer.setUint8(offset + pos, (value & 0x7f) | 0x80);
    value >>= 7;
    pos++;
  }
  buffer.setUint8(offset + pos, value & 0x7f);
  return pos + 1;
}

({int value, int bytesRead})? _readVarint(Uint8List data, int offset) {
  int result = 0;
  int shift = 0;
  int pos = 0;
  
  while (true) {
    if (offset + pos >= data.length) return null;
    final byte = data[offset + pos];
    result |= (byte & 0x7f) << shift;
    pos++;
    if ((byte & 0x80) == 0) break;
    shift += 7;
    if (shift > 63) return null; // overflow
  }
  
  return (value: result, bytesRead: pos);
}
