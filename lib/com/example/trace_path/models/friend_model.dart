/// 好友模型
class Friend {
  final String phoneNumber; // 唯一ID
  final String name;
  final String emoji;
  final double? lat;
  final double? lng;
  final DateTime? lastUpdateTime;
  final String? address;

  Friend({
    required this.phoneNumber,
    required this.name,
    required this.emoji,
    this.lat,
    this.lng,
    this.lastUpdateTime,
    this.address,
  });

  Map<String, dynamic> toJson() {
    return {
      'phoneNumber': phoneNumber,
      'name': name,
      'emoji': emoji,
      'lat': lat,
      'lng': lng,
      'lastUpdateTime': lastUpdateTime?.toIso8601String(),
      'address': address,
    };
  }

  factory Friend.fromJson(Map<String, dynamic> json) {
    return Friend(
      phoneNumber: json['phoneNumber'] as String,
      name: json['name'] as String,
      emoji: json['emoji'] as String,
      lat: json['lat'] as double?,
      lng: json['lng'] as double?,
      lastUpdateTime: json['lastUpdateTime'] != null
          ? DateTime.parse(json['lastUpdateTime'] as String)
          : null,
      address: json['address'] as String?,
    );
  }

  Friend copyWith({
    String? phoneNumber,
    String? name,
    String? emoji,
    double? lat,
    double? lng,
    DateTime? lastUpdateTime,
    String? address,
  }) {
    return Friend(
      phoneNumber: phoneNumber ?? this.phoneNumber,
      name: name ?? this.name,
      emoji: emoji ?? this.emoji,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      lastUpdateTime: lastUpdateTime ?? this.lastUpdateTime,
      address: address ?? this.address,
    );
  }
}
