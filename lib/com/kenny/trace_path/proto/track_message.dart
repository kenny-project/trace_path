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
  /// 格式: timestamp_ms(varint) + latitude(double) + longitude(double) + altitude(float) + speed(float) + accuracy(float)
  /// 返回: (编码字节, 实际编码长度)
  (Uint8List, int) encode() {
    // 计算 varint 实际长度
    int varintLen = 1;
    int tmp = timestampMs;
    while (tmp > 0x7f) {
      tmp >>= 7;
      varintLen++;
    }
    
    // 实际编码长度 = varint + 28 (double+double+float+float+float)
    final actualSize = varintLen + 28;
    final buffer = ByteData(actualSize);
    int offset = 0;
    
    // timestamp_ms: varint
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
    
    return (buffer.buffer.asUint8List(), actualSize);
  }

  /// 解码从二进制
  /// 返回: (TrackPointMessage?, 实际编码长度)
  static (TrackPointMessage?, int) decode(Uint8List data, int offset) {
    try {
      final buffer = ByteData.sublistView(data, offset);
      int pos = 0;
      
      // timestamp_ms: varint
      final timestampResult = _readVarint(data, offset);
      if (timestampResult == null) return (null, 0);
      final varintLen = timestampResult.bytesRead;
      pos += varintLen;
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
      
      final msg = TrackPointMessage(
        timestampMs: timestampMs,
        latitude: latitude,
        longitude: longitude,
        altitude: altitude,
        speed: speed,
        accuracy: accuracy,
      );
      // 实际编码长度 = varint长度 + 28
      return (msg, varintLen + 28);
    } catch (e) {
      return (null, 0);
    }
  }
  
  /// 估算编码长度（不含实际varint解析，用于初始化Buffer）
  int get encodedSize => 44;
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
