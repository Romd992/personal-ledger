class Book {
  final int? id;
  final String name;
  final int isDefault; // 1=默认账本不可删
  final int sortOrder;
  final String createdAt;

  Book({
    this.id,
    required this.name,
    this.isDefault = 0,
    this.sortOrder = 0,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'is_default': isDefault,
      'sort_order': sortOrder,
      'created_at': createdAt,
    };
  }

  factory Book.fromMap(Map<String, dynamic> map) {
    return Book(
      id: map['id'] as int?,
      name: map['name'] as String,
      isDefault: map['is_default'] as int? ?? 0,
      sortOrder: map['sort_order'] as int? ?? 0,
      createdAt: map['created_at'] as String,
    );
  }

  Book copyWith({
    int? id,
    String? name,
    int? isDefault,
    int? sortOrder,
    String? createdAt,
  }) {
    return Book(
      id: id ?? this.id,
      name: name ?? this.name,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
