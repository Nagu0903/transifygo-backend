import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String? id;
  final String name;
  final String phone;
  final String password;
  final String role;
  final DateTime? createdAt;
  final bool isBlocked;
  final String? profileImage;
  final String? truckType;
  final String? truckNumber;
  final String? city;
  final String? fullName;

  UserModel({
    this.id,
    required this.name,
    required this.phone,
    required this.password,
    required this.role,
    this.createdAt,
    this.isBlocked = false,
    this.profileImage,
    this.truckType,
    this.truckNumber,
    this.city,
    this.fullName,
  });

  factory UserModel.fromMap(Map<String, dynamic> map, String docId) {
    return UserModel(
      id: docId,
      name: map['name'] ?? '',
      phone: map['phone'] ?? '',
      password: map['password'] ?? '',
      role: map['role'] ?? '',
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      isBlocked: map['isBlocked'] ?? false,
      profileImage: map['profileImage'],
      truckType: map['truckType'],
      truckNumber: map['truckNumber'],
      city: map['city'],
      fullName: map['fullName'] ?? map['name'], // Fallback to name
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'phone': phone,
      'password': password,
      'role': role,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
      'isBlocked': isBlocked,
      'profileImage': profileImage,
      'truckType': truckType,
      'truckNumber': truckNumber,
      'city': city,
      'fullName': fullName ?? name,
    };
  }
}
