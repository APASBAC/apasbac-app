import 'animal_model.dart';
import '../utils/image_url.dart';

class MonitoringMedia {
  final String id;
  final String url;
  final String type; // 'IMAGE' | 'VIDEO'

  const MonitoringMedia({
    required this.id,
    required this.url,
    required this.type,
  });

  factory MonitoringMedia.fromJson(dynamic json) {
    // Objeto completo: { id, url, type }
    if (json is Map<String, dynamic>) {
      final type = (json['type'] ?? 'IMAGE').toString().toUpperCase();
      final url = json['url']?.toString();
      return MonitoringMedia(
        id: (json['id'] ?? url ?? '').toString(),
        url: type == 'VIDEO' ? normalizeVideoUrl(url) : normalizeImageUrl(url),
        type: type,
      );
    }
    // String pura (URL direta de imageUrls[])
    if (json is String) {
      return MonitoringMedia(
        id: json,
        url: normalizeImageUrl(json),
        type: 'IMAGE',
      );
    }
    return const MonitoringMedia(id: '', url: '', type: 'IMAGE');
  }

  bool get isVideo => type == 'VIDEO';
}

class MonitoringModel {
  final String id;
  final int animalId;
  final String tutorId;
  final String? tutorName;
  final String? tutorEmail;
  final String status;
  final String? notes;
  final String? reviewNotes;
  final List<MonitoringMedia> medias;
  final AnimalModel? animal;
  final DateTime? createdAt;
  final DateTime? dueDate;

  const MonitoringModel({
    required this.id,
    required this.animalId,
    required this.tutorId,
    this.tutorName,
    this.tutorEmail,
    required this.status,
    this.notes,
    this.reviewNotes,
    required this.medias,
    this.animal,
    this.createdAt,
    this.dueDate,
  });

  factory MonitoringModel.fromJson(Map<String, dynamic> json) {
    // O backend salva mídias em videoUrl (String?) + imageUrls (List<String>)
    // e não em um campo 'medias'. Monta a lista aqui.
    final List<MonitoringMedia> medias = [];

    final videoUrl = json['videoUrl'] as String?;
    if (videoUrl != null && videoUrl.isNotEmpty) {
      medias.add(
        MonitoringMedia(
          id: videoUrl,
          url: normalizeVideoUrl(videoUrl),
          type: 'VIDEO',
        ),
      );
    }

    final imageUrls = json['imageUrls'];
    if (imageUrls is List) {
      for (final url in imageUrls) {
        if (url is String && url.isNotEmpty) {
          medias.add(
            MonitoringMedia(
              id: url,
              url: normalizeImageUrl(url),
              type: 'IMAGE',
            ),
          );
        }
      }
    }

    // Compatibilidade: se vier campo 'medias' da API (futuro)
    if (medias.isEmpty && json['medias'] is List) {
      final raw = json['medias'] as List<dynamic>;
      medias.addAll(raw.map((m) => MonitoringMedia.fromJson(m)));
    }

    final animal = json['animal'] is Map
        ? AnimalModel.fromJson(Map<String, dynamic>.from(json['animal'] as Map))
        : null;
    final user = json['user'] ?? json['tutor'];
    final rawAnimalId = json['animalId'];
    final animalId = rawAnimalId is int
        ? rawAnimalId
        : int.tryParse(rawAnimalId?.toString() ?? '') ?? animal?.id ?? 0;

    return MonitoringModel(
      id: (json['id'] ?? '').toString(),
      animalId: animalId,
      tutorId: (json['userId'] ?? json['tutorId'] ?? '').toString(),
      tutorName: user is Map ? user['fullName']?.toString() : null,
      tutorEmail: user is Map ? user['email']?.toString() : null,
      status: json['status'] ?? 'PENDING',
      notes: json['notes'],
      reviewNotes: json['reviewNotes'],
      medias: medias,
      animal: animal,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.tryParse(json['dueDate'])
          : null,
    );
  }

  MonitoringModel withAnimal(AnimalModel? full) => MonitoringModel(
    id: id,
    animalId: animalId,
    tutorId: tutorId,
    tutorName: tutorName,
    tutorEmail: tutorEmail,
    status: status,
    notes: notes,
    reviewNotes: reviewNotes,
    medias: medias,
    animal: full == null ? animal : (animal?.mergedWith(full) ?? full),
    createdAt: createdAt,
    dueDate: dueDate,
  );

  String get statusLabel => switch (status) {
    'PENDING' => 'Aguardando envio',
    'IN_REVIEW' => 'Em análise',
    'APPROVED' => 'Aprovado',
    'REJECTED' => 'Rejeitado',
    _ => status,
  };

  bool get canSubmit => status == 'PENDING' || status == 'REJECTED';
  bool get isUnderReview => status == 'IN_REVIEW';
  bool get isApproved => status == 'APPROVED';
  bool get isRejected => status == 'REJECTED';
}
