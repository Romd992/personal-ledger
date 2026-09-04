class ExpenseType {
  final int? id;
  final String name;
  final String icon; // Material图标名称或codePoint
  final int sortOrder;
  final bool isBuiltIn; // 是否内置（内置不可删除）

  ExpenseType({
    this.id,
    required this.name,
    this.icon = 'category',
    this.sortOrder = 0,
    this.isBuiltIn = false,
  });

  // 内置8种支出类型
  static List<ExpenseType> get builtInTypes => [
    ExpenseType(name: '采购支出', icon: 'shopping_cart', sortOrder: 0, isBuiltIn: true),
    ExpenseType(name: '生活支出', icon: 'restaurant', sortOrder: 1, isBuiltIn: true),
    ExpenseType(name: '运营支出', icon: 'business', sortOrder: 2, isBuiltIn: true),
    ExpenseType(name: '运输支出', icon: 'local_shipping', sortOrder: 3, isBuiltIn: true),
    ExpenseType(name: '办公支出', icon: 'desk', sortOrder: 4, isBuiltIn: true),
    ExpenseType(name: '工资支出', icon: 'payments', sortOrder: 5, isBuiltIn: true),
    ExpenseType(name: '税费支出', icon: 'receipt', sortOrder: 6, isBuiltIn: true),
    ExpenseType(name: '其他支出', icon: 'more_horiz', sortOrder: 7, isBuiltIn: true),
  ];

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'sort_order': sortOrder,
      'is_built_in': isBuiltIn ? 1 : 0,
    };
  }

  factory ExpenseType.fromMap(Map<String, dynamic> map) {
    return ExpenseType(
      id: map['id'] as int?,
      name: map['name'] as String,
      icon: map['icon'] as String? ?? 'category',
      sortOrder: (map['sort_order'] as num?)?.toInt() ?? 0,
      isBuiltIn: (map['is_built_in'] as num?)?.toInt() == 1,
    );
  }

  ExpenseType copyWith({
    int? id,
    String? name,
    String? icon,
    int? sortOrder,
    bool? isBuiltIn,
  }) {
    return ExpenseType(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      sortOrder: sortOrder ?? this.sortOrder,
      isBuiltIn: isBuiltIn ?? this.isBuiltIn,
    );
  }
}
