enum DeviceStatus { pending, approved, rejected, unknown }

class Device {
  final String id;
  final String name;
  final DeviceStatus status;
  final bool online;
  final String? firstSeen;
  final String? approvedAt;

  const Device({
    required this.id,
    required this.name,
    required this.status,
    this.online = false,
    this.firstSeen,
    this.approvedAt,
  });

  factory Device.fromMap(Map<String, dynamic> map) => Device(
        id: map['id'] as String,
        name: map['name'] as String? ?? 'Inconnu',
        status: _parseStatus(map['status'] as String?),
        online: map['online'] as bool? ?? false,
        firstSeen: map['first_seen'] as String?,
        approvedAt: map['approved_at'] as String?,
      );

  static DeviceStatus _parseStatus(String? s) => switch (s) {
        'pending' => DeviceStatus.pending,
        'approved' => DeviceStatus.approved,
        'rejected' => DeviceStatus.rejected,
        _ => DeviceStatus.unknown,
      };

  Device copyWith({DeviceStatus? status, bool? online}) => Device(
        id: id,
        name: name,
        status: status ?? this.status,
        online: online ?? this.online,
        firstSeen: firstSeen,
        approvedAt: approvedAt,
      );
}
