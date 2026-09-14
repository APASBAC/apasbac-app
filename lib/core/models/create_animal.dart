class CreateAnimal {
  final String name, description, breed, sex, size, temperament;
  final List<String> vaccines, photoUrls;
  final bool escapeTendency;
  const CreateAnimal(
      {required this.name,
      required this.description,
      required this.breed,
      required this.sex,
      required this.size,
      required this.temperament,
      this.vaccines = const [],
      this.photoUrls = const [],
      this.escapeTendency = false});

  Map<String, dynamic> toJson() {
    if (name.trim().isEmpty ||
        breed.trim().isEmpty ||
        description.trim().isEmpty ||
        !['MALE', 'FEMALE'].contains(sex) ||
        !['SMALL', 'MEDIUM', 'LARGE', 'EXTRA_LARGE'].contains(size)) {
      throw ArgumentError('Preencha os dados obrigatórios do animal.');
    }
    if (photoUrls.length > 3 ||
        photoUrls.any((url) {
          final uri = Uri.tryParse(url);
          return uri == null || uri.scheme != 'https' || uri.host.isEmpty;
        })) {
      throw ArgumentError('Informe no máximo 3 URLs de fotos HTTPS.');
    }
    return {
      'name': name.trim(),
      'description': description.trim(),
      'breed': breed.trim(),
      'sex': sex,
      'size': size,
      'temperament': temperament.trim(),
      'vaccines': vaccines,
      'escapeTendency': escapeTendency,
      'photoUrls': photoUrls
    };
  }
}
