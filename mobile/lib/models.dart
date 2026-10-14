class SessionUser {
  const SessionUser({
    required this.id,
    required this.name,
    required this.username,
    required this.profile,
  });

  final int id;
  final String name;
  final String username;
  final String profile;

  factory SessionUser.fromJson(Map<String, dynamic> json) => SessionUser(
        id: (json['idUsuario'] as num).toInt(),
        name: json['nome'] as String? ?? '',
        username: json['username'] as String? ?? '',
        profile: json['perfil'] as String? ?? '',
      );
}

class SelectedCopy {
  const SelectedCopy({
    required this.id,
    required this.code,
    required this.title,
    required this.status,
  });

  final int id;
  final String code;
  final String title;
  final String status;

  factory SelectedCopy.fromJson(Map<String, dynamic> json) => SelectedCopy(
        id: (json['idExemplar'] as num).toInt(),
        code: json['codigoTombo'] as String? ?? '',
        title: json['titulo'] as String? ?? '',
        status: json['situacao'] as String? ?? '',
      );
}

String formatDate(Object? value) {
  if (value == null) return '—';
  final date = DateTime.tryParse(value.toString())?.toLocal();
  if (date == null) return '—';
  final day = date.day.toString().padLeft(2, '0');
  final month = date.month.toString().padLeft(2, '0');
  return '$day/$month/${date.year}';
}
