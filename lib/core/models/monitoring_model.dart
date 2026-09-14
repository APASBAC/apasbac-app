import 'animal_model.dart';

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
      return MonitoringMedia(
        id: json['id'] ?? '',
        url: json['url'] ?? '',
        type: json['type'] ?? 'IMAGE',
      );
    }
    // String pura (URL direta de imageUrls[])
    if (json is String) {
      return MonitoringMedia(id: json, url: json, type: 'IMAGE');
    }
    return const MonitoringMedia(id: '', url: '', type: 'IMAGE');
  }

  bool get isVideo => type == 'VIDEO';
}

class MonitoringModel {
  final String id;
  final int animalId;
  final String tutorId;
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
      medias.add(MonitoringMedia(id: videoUrl, url: videoUrl, type: 'VIDEO'));
    }

    final imageUrls = json['imageUrls'];
    if (imageUrls is List) {
      for (final url in imageUrls) {
        if (url is String && url.isNotEmpty) {
          medias.add(MonitoringMedia(id: url, url: url, type: 'IMAGE'));
        }
      }
    }

    // Compatibilidade: se vier campo 'medias' da API (futuro)
    if (medias.isEmpty && json['medias'] is List) {
      final raw = json['medias'] as List<dynamic>;
      medias.addAll(raw.map((m) => MonitoringMedia.fromJson(m)));
    }

    return MonitoringModel(
      id: json['id'] ?? '',
      animalId: json['animalId'] ?? 0,
      tutorId: json['userId'] ?? json['tutorId'] ?? '',
      status: json['status'] ?? 'PENDING',
      notes: json['notes'],
      reviewNotes: json['reviewNotes'],
      medias: medias,
      animal: json['animal'] != null
          ? AnimalModel.fromJson(json['animal'] as Map<String, dynamic>)
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'])
          : null,
      dueDate: json['dueDate'] != null
          ? DateTime.tryParse(json['dueDate'])
          : null,
    );
  }

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