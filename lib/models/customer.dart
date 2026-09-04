class Customer {
  final int? id;
  final String name;
  final String? contact; // 联系人
  final String? phone;
  final String? address;
  final String? remark;
  final String createdAt;
  final String updatedAt;

  Customer({
    this.id,
    required this.name,
    this.contact,
    this.phone,
    this.address,
    this.remark,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'contact': contact,
      'phone': phone,
      'address': address,
      'remark': remark,
      'created_at': createdAt,
      'updated_at': updatedAt,
    };
  }

  factory Customer.fromMap(Map<String, dynamic> map) {
    return Customer(
      id: map['id'] as int?,
      name: map['name'] as String,
      contact: map['contact'] as String?,
      phone: map['phone'] as String?,
      address: map['address'] as String?,
      remark: map['remark'] as String?,
      createdAt: map['created_at'] as String,
      updatedAt: map['updated_at'] as String,
    );
  }
}
