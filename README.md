# APASBAC App — Flutter

App mobile para tutores de animais adotados pela APASBAC.

## Funcionalidades
- Login / Cadastro com JWT + Refresh Token automático
- Recuperação de senha por e-mail
- Listagem dos animais adotados pelo usuário
- Detalhes completos do animal (fotos em carrossel, vacinas, temperamento, etc.)
- Lista de monitoramentos do tutor com status em tempo real
- Detalhes do monitoramento (mídias enviadas, nota de revisão, status)
- Envio de relatório: até 5 fotos + 1 vídeo via multipart/form-data

---

## Setup

### 1. Instalar dependências
```bash
flutter pub get
```

### 2. Configurar a URL da API
Edite o arquivo `lib/core/api/api_client.dart`:
```dart
const String kBaseUrl = 'https://SEU_DOMINIO_AQUI/api/v1';
```

### 3. Android — Permissões
Abra `android/app/src/main/AndroidManifest.xml` e adicione dentro de `<manifest>`:
```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
<uses-permission android:name="android.permission.READ_MEDIA_VIDEO"/>
<uses-permission android:name="android.permission.CAMERA"/>
<uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"
    android:maxSdkVersion="32"/>
```

Adicione dentro de `<application>`:
```xml
<provider
    android:name="androidx.core.content.FileProvider"
    android:authorities="${applicationId}.fileprovider"
    android:exported="false"
    android:grantUriPermissions="true">
    <meta-data
        android:name="android.support.FILE_PROVIDER_PATHS"
        android:resource="@xml/file_paths"/>
</provider>
```

Crie o arquivo `android/app/src/main/res/xml/file_paths.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<paths>
    <external-path name="external_files" path="."/>
</paths>
```

### 4. iOS — Info.plist
Adicione ao `ios/Runner/Info.plist`:
```xml
<key>NSCameraUsageDescription</key>
<string>Necessário para tirar fotos do animal</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Necessário para selecionar fotos e vídeos do animal</string>
<key>NSMicrophoneUsageDescription</key>
<string>Necessário para gravar vídeo</string>
```

### 5. Rodar o app
```bash
flutter run
```

---

## Estrutura do projeto
```
lib/
├── main.dart                  # Entry point
├── router.dart                # GoRouter
├── providers.dart             # Riverpod providers globais
└── core/
    ├── api/
    │   └── api_client.dart    # Dio + interceptor JWT refresh
    ├── models/
    │   ├── user_model.dart
    │   ├── animal_model.dart
    │   └── monitoring_model.dart
    └── services/
        ├── auth_service.dart
        ├── animal_service.dart
        └── monitoring_service.dart
features/
├── auth/presentation/screens/
│   ├── login_screen.dart
│   ├── register_screen.dart
│   ├── forgot_password_screen.dart
│   └── home_screen.dart
├── animals/presentation/screens/
│   ├── my_animals_screen.dart
│   └── animal_detail_screen.dart
└── monitoring/presentation/screens/
    ├── monitoring_list_screen.dart
    ├── monitoring_detail_screen.dart
    └── monitoring_submit_screen.dart
```

---

## Observações importantes

### Endpoint "meus animais"
A API não possui um endpoint direto `/animals/mine`. O `AnimalService.getMyAnimals()` 
busca `/animals?isAdopted=true` e filtra pelo `adoptedById == userId` no cliente.

**Se a API retornar apenas os animais do próprio tutor autenticado** (comportamento 
mais comum com roles), basta remover o `.where(...)` em `animal_service.dart`.

### Resposta do login
O `AuthService` espera que o endpoint `/auth/login` retorne:
```json
{
  "accessToken": "...",
  "refreshToken": "...",
  "user": { "id": "...", "fullName": "...", ... }
}
```
Se o `user` vier em outra chave ou inline, ajuste o `UserModel.fromJson` em 
`auth_service.dart`.

### Refresh token
O interceptor em `api_client.dart` faz o refresh automaticamente em qualquer 
resposta `401`, re-tenta a requisição original e redireciona para o login se 
o refresh falhar.
