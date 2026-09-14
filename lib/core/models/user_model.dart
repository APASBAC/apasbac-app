class UserModel {
  final String id;
  final String fullName;
  final String email;
  final String phone;
  final String role;

  const UserModel({
    required this.id,
    required this.fullName,
    required this.email,
    required this.phone,
    required this.role,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) => UserModel(
        id: json['id'] ?? '',
        fullName: json['fullName'] ?? '',
        email: json['email'] ?? '',
        phone: json['phone'] ?? '',
        role: json['role'] ?? 'USER',
      );

  /// Pode acessar /monitoring/mine (endpoint exclusivo para tutores)
  bool get isTutor => role == 'TUTOR';

  /// Admin ou Staff — acessa /monitoring (lista geral)
  bool get isAdminOrStaff => role == 'ADMIN' || role == 'STAFF';

  /// Tem acesso à área de monitoramentos (por qualquer endpoint)
  bool get canAccessMonitoring => isTutor || isAdminOrStaff;
}