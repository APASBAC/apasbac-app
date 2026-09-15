import 'package:flutter/material.dart';

abstract final class SemanticColors {
  static const pending = Color(0xFF93600D);
  static const review = Color(0xFF245F91);
  static const approved = Color(0xFF33704B);
  static const rejected = Color(0xFF8B1A1A);
  static Color status(String status) => switch (status) {
        'PENDING' => pending,
        'IN_REVIEW' => review,
        'APPROVED' => approved,
        'REJECTED' => rejected,
        _ => const Color(0xFF78534A),
      };
  static Color role(String role) => switch (role) {
        'ADMIN' => const Color(0xFF70418A),
        'STAFF' => review,
        'TUTOR' => approved,
        _ => const Color(0xFF78534A),
      };
  static String roleLabel(String role) => switch (role) {
        'ADMIN' => 'Admin',
        'STAFF' => 'Equipe',
        'TUTOR' => 'Tutor',
        'USER' => 'Usuário',
        _ => role,
      };
}

class RoleBadge extends StatelessWidget {
  final String role;
  const RoleBadge({super.key, required this.role});
  @override
  Widget build(BuildContext context) {
    final color = SemanticColors.role(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          borderRadius: BorderRadius.circular(8)),
      child: Text(SemanticColors.roleLabel(role),
          style: TextStyle(
              color: color, fontSize: 13, fontWeight: FontWeight.w700)),
    );
  }
}
