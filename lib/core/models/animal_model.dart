import '../utils/image_url.dart';

class AnimalPhoto {
  final String url;
  final bool isPrimary;

  const AnimalPhoto({required this.url, this.isPrimary = false});

  factory AnimalPhoto.fromJson(dynamic json) {
    // Formato objeto: { url | secure_url, isPrimary }
    if (json is Map) {
      return AnimalPhoto(
        url: normalizeImageUrl(
          (json['url'] ?? json['secure_url'] ?? json['secureUrl'])?.toString(),
        ),
        isPrimary: json['isPrimary'] == true,
      );
    }
    // Formato da API atual: lista de strings com a URL direta
    if (json is String) {
      return AnimalPhoto(url: normalizeImageUrl(json));
    }
    return const AnimalPhoto(url: '');
  }
}

String _str(dynamic v) => v == null ? '' : v.toString().trim();

int _int(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(_str(v)) ?? 0;
}

bool _bool(dynamic v) => v == true || v?.toString().toLowerCase() == 'true';

class AnimalModel {
  final int id;
  final String uuid;
  final String name;
  final String description;
  final String species;
  final String breed;
  final String sex;
  final String size;
  final List<String> vaccines;
  final String temperament;
  final bool escapeTendency;
  final bool isAdopted;
  final List<AnimalPhoto> photos;
  final String? adoptedById;
  final String? adopterName;
  final DateTime? createdAt;

  const AnimalModel({
    required this.id,
    required this.uuid,
    required this.name,
    required this.description,
    this.species = '',
    required this.breed,
    required this.sex,
    required this.size,
    required this.vaccines,
    required this.temperament,
    required this.escapeTendency,
    required this.isAdopted,
    required this.photos,
    this.adoptedById,
    this.adopterName,
    this.createdAt,
  });

  factory AnimalModel.fromJson(Map<String, dynamic> json) {
    final rawPhotos = json['photos'] ?? json['photoUrls'];
    final adoptedBy = json['adoptedBy'];
    return AnimalModel(
      id: _int(json['id']),
      uuid: _str(json['uuid']),
      name: _str(json['name']),
      description: _str(json['description']),
      species: _str(json['species']),
      breed: _str(json['breed']),
      sex: _str(json['sex']).toUpperCase(),
      size: _str(json['size']).toUpperCase(),
      vaccines: (json['vaccines'] is List)
          ? (json['vaccines'] as List).map(_str).toList()
          : const [],
      temperament: _str(json['temperament']),
      escapeTendency: _bool(json['escapeTendency']),
      isAdopted: _bool(json['isAdopted']),
      photos: (rawPhotos is List ? rawPhotos : const [])
          .map(AnimalPhoto.fromJson)
          .where((p) => p.url.isNotEmpty)
          .toList(),
      adoptedById:
          json['adoptedById']?.toString() ??
          (adoptedBy is Map ? adoptedBy['id']?.toString() : null),
      adopterName:
          adoptedBy is Map ? adoptedBy['fullName']?.toString() : null,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
    );
  }

  /// Combina dados parciais (ex.: animal embutido no monitoramento, que vem
  /// só com id/nome/espécie/raça) com o cadastro completo do animal.
  AnimalModel mergedWith(AnimalModel full) => AnimalModel(
    id: id != 0 ? id : full.id,
    uuid: uuid.isNotEmpty ? uuid : full.uuid,
    name: full.name.isNotEmpty ? full.name : name,
    description: full.description.isNotEmpty ? full.description : description,
    species: full.species.isNotEmpty ? full.species : species,
    breed: full.breed.isNotEmpty ? full.breed : breed,
    sex: full.sex.isNotEmpty ? full.sex : sex,
    size: full.size.isNotEmpty ? full.size : size,
    vaccines: full.vaccines.isNotEmpty ? full.vaccines : vaccines,
    temperament: full.temperament.isNotEmpty ? full.temperament : temperament,
    escapeTendency: full.escapeTendency || escapeTendency,
    isAdopted: full.isAdopted || isAdopted,
    photos: full.photos.isNotEmpty ? full.photos : photos,
    adoptedById: full.adoptedById ?? adoptedById,
    adopterName: full.adopterName ?? adopterName,
    createdAt: full.createdAt ?? createdAt,
  );

  bool get hasSex => sexLabel.isNotEmpty;

  String get sexLabel => switch (sex) {
    'MALE' || 'MACHO' || 'M' => 'Macho',
    'FEMALE' || 'FEMEA' || 'FÊMEA' || 'F' => 'Fêmea',
    _ => '',
  };

  String get sizeLabel => switch (size) {
    'SMALL' => 'Pequeno',
    'MEDIUM' => 'Médio',
    'LARGE' => 'Grande',
    'EXTRA_LARGE' => 'Extra Grande',
    _ => size,
  };

  /// Raça para exibição; quando a raça não foi informada, usa a espécie.
  String get breedLabel {
    if (breed.isNotEmpty) return breed;
    if (species.isNotEmpty && species != 'Não informada') return species;
    return 'Raça não informada';
  }

  /// "Raça · Sexo", omitindo o que não foi informado.
  String get summary => [breedLabel, if (hasSex) sexLabel].join(' · ');

  AnimalPhoto? get primaryPhoto {
    if (photos.isEmpty) return null;
    return photos.firstWhere((p) => p.isPrimary, orElse: () => photos.first);
  }
}
