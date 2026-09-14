class AnimalPhoto {
  final String url;
  final bool isPrimary;

  const AnimalPhoto({required this.url, this.isPrimary = false});

  factory AnimalPhoto.fromJson(dynamic json) {
    // Rota admin: { url, isPrimary }
    if (json is Map<String, dynamic>) {
      return AnimalPhoto(
        url: json['url'] ?? '',
        isPrimary: json['isPrimary'] ?? false,
      );
    }
    // Rota pública: lista de strings de URL diretas
    if (json is String) {
      return AnimalPhoto(url: json, isPrimary: false);
    }
    return const AnimalPhoto(url: '');
  }
}

class AnimalModel {
  final int id;
  final String uuid;
  final String name;
  final String description;
  final String breed;
  final String sex;
  final String size;
  final List<String> vaccines;
  final String temperament;
  final bool escapeTendency;
  final bool isAdopted;
  final List<AnimalPhoto> photos;
  final String? adoptedById;
  final DateTime? createdAt;

  const AnimalModel({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
    required this.breed,
    required this.sex,
    required this.size,
    required this.vaccines,
    required this.temperament,
    required this.escapeTendency,
    required this.isAdopted,
    required this.photos,
    this.adoptedById,
    this.createdAt,
  });

  factory AnimalModel.fromJson(Map<String, dynamic> json) => AnimalModel(
        id: json['id'] ?? 0,
        uuid: json['uuid'] ?? '',
        name: json['name'] ?? '',
        description: json['description'] ?? '',
        breed: json['breed'] ?? '',
        sex: json['sex'] ?? '',
        size: json['size'] ?? '',
        vaccines: List<String>.from(json['vaccines'] ?? []),
        temperament: json['temperament'] ?? '',
        escapeTendency: json['escapeTendency'] ?? false,
        isAdopted: json['isAdopted'] ?? false,
        // Aceita tanto List<String> (rota pública) quanto List<Map> (rota admin)
        photos: (json['photos'] as List<dynamic>? ?? [])
            .map((p) => AnimalPhoto.fromJson(p))
            .toList(),
        adoptedById: json['adoptedById'],
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'])
            : null,
      );

  String get sexLabel => sex == 'MALE' ? 'Macho' : 'Fêmea';

  String get sizeLabel => switch (size) {
        'SMALL' => 'Pequeno',
        'MEDIUM' => 'Médio',
        'LARGE' => 'Grande',
        'EXTRA_LARGE' => 'Extra Grande',
        _ => size,
      };

  AnimalPhoto? get primaryPhoto {
    if (photos.isEmpty) return null;
    return photos.firstWhere((p) => p.isPrimary, orElse: () => photos.first);
  }
}