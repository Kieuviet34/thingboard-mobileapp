import 'package:flutter/foundation.dart';
import 'package:thingsboard_democloud_app/core/models/entity_id.dart';

/// Customer model from `/api/customerInfos/all`, `/api/customers`, and `/api/customer/info/{id}`.
@immutable
class TbCustomerInfo {
  const TbCustomerInfo({
    required this.id,
    required this.title,
    this.country = '',
    this.state = '',
    this.city = '',
    this.address = '',
    this.address2 = '',
    this.zip = '',
    this.phone = '',
    this.email = '',
    this.parentCustomerId,
    this.createdTime = 0,
  });

  factory TbCustomerInfo.fromJson(Map<String, dynamic> json) {
    final idObj = EntityId.maybeFromJson(json['id']);
    final parentObj = EntityId.maybeFromJson(json['parentCustomerId']);
    return TbCustomerInfo(
      id: idObj?.id ?? (json['id'] as String? ?? ''),
      title: json['title'] as String? ?? json['name'] as String? ?? '',
      country: json['country'] as String? ?? '',
      state: json['state'] as String? ?? '',
      city: json['city'] as String? ?? '',
      address: json['address'] as String? ?? '',
      address2: json['address2'] as String? ?? '',
      zip: json['zip'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      email: json['email'] as String? ?? '',
      parentCustomerId: parentObj?.id,
      createdTime: (json['createdTime'] as num?)?.toInt() ?? 0,
    );
  }

  final String id;
  final String title;
  final String country;
  final String state;
  final String city;
  final String address;
  final String address2;
  final String zip;
  final String phone;
  final String email;
  final String? parentCustomerId;
  final int createdTime;

  String get locationSummary {
    final parts = [city, state, country].where((s) => s.trim().isNotEmpty);
    return parts.join(', ');
  }
}
