# Versionamento e atualizações Android

## Auditoria de implantação

- App: Flutter 3.38.7 / Dart 3.10.7, Riverpod 2, GoRouter 13, Dio 5; Android em Kotlin 2.2.20 / AGP 8.11.1 / Java 17.
- Android: minSdk 24, targetSdk 36, compileSdk 36, herdados dessa versão do Flutter.
- Identificador preservado: `com.example.apasbac_app`. Não mudar depois da primeira distribuição.
- Versão anterior: `1.0.0+1`; primeira versão preparada com atualizador: `1.0.1+2`.
- API: NestJS 10 / TypeScript, Prisma / PostgreSQL, autenticação JWT access + refresh; URL atual `https://apasbac-api.vercel.app/api/v1`.
- Distribuição confirmada: APK direto, fora da Google Play; nenhum APK havia sido distribuído.
- Assinatura anterior: release usava debug. Agora produção exige chave própria, por Secrets ou `android/key.properties` ignorado pelo Git.
- Repositórios públicos confirmados: `APASBAC/apasbac-app` e `hhartur/apasbac-api`. O cliente não recebe tokens GitHub.
- Não havia GitHub Actions. O app em `apasbac-app` e o manifesto usam **source**; o worktree `apasbac-app-info` permanece na **main**. A API usa **main**, com CI nessa branch.
- Não havia telemetria de produto. Foram adicionados eventos mínimos de atualização; autenticação existente é reaproveitada.

## Fonte de versão e política

Altere somente `version` no `pubspec.yaml` para definir a versão do APK:

```yaml
version: 1.0.2+3
```

`1.0.2` é o nome apresentado; `3` é o inteiro comparado. Nunca compare nomes de versão. Cada release exige um código maior e uma tag nova. Não use `--build-name` / `--build-number` no pipeline: o verificador detecta divergências com o pubspec.

Em `update/release-notes.json`, configure `mandatory`, `minimumSupportedVersionCode` e notas. O mínimo deve estar entre 1 e o código publicado e não pode diminuir. O pipeline impede diminuir o mínimo porque dispositivos offline conservam a última restrição conhecida.

O manifesto público é:

`https://raw.githubusercontent.com/APASBAC/apasbac-app/source/update/version.json`

**`update/version.json` é gerado pelo workflow somente depois que o APK real está publicado e foi baixado anonimamente e verificado.** Antes da primeira release, 404 é esperado e não impede o uso do app. Não copie `version.example.json` para esse endereço: o exemplo demonstra o schema e contém hash/tamanho ilustrativos, sem uma release correspondente.

Campos adicionais são ignorados. Campos obrigatórios inválidos impedem download. Manifesto limitado a schema 1 e canal configurado, inteiros positivos, hash SHA-256, tamanho até 1 GiB, data UTC, notas limitadas e URL HTTPS da Release deste repositório. Não redirecionamos a consulta do manifesto nem enviamos autenticação ao GitHub.

## Fluxo e responsabilidades

`lib/core/update` contém manifesto tipado, repositório/cache, gerenciador de estados, integração Dio, telemetria e tela. `MaterialApp.builder` mantém a tela independente das navegações e usa o tema existente. “Depois” dura a sessão; atualização obrigatória bloqueia interação, foco e acessibilidade das telas principais.

O Android informa a versão realmente instalada pelo PackageManager. Na inicialização o app consulta o RAW, com limite de 10 segundos e cache-busting em intervalos de cinco minutos. A última resposta válida fica em SharedPreferences. Um mínimo já conhecido continua sendo aplicado offline. Versões suportadas abrem normalmente quando não há rede ou o GitHub falha.

O servidor usa o mesmo manifesto, cache de cinco minutos, requisições concorrentes agrupadas e persistência do último manifesto válido na tabela AppConfig existente. A chave `android_update_stable_manifest_cache` é apenas cache interno: não é uma segunda fonte de configuração; não editar manualmente. Uma indisponibilidade sem nenhum manifesto previamente conhecido libera requisições para não inutilizar o app. Com cache válido, o mínimo continua aplicado.

O interceptor Dio envia `X-App-Version-Code`, `X-App-Version-Name` e `X-App-Platform: android` nas chamadas da API, inclusive refresh. Uma resposta `426` com `APP_UPDATE_REQUIRED` abre a atualização obrigatória e persiste o mínimo, independentemente da tela atual. URLs recebidas na resposta 426 não substituem a origem GitHub confiável.

Endpoints da API (mantendo o prefixo existente):

- `GET /api/v1/app/version`: público, manifesto dentro do envelope padrão `{ success, data, timestamp }`; 503 enquanto não existir resposta válida.
- `POST /api/v1/app/update-events`: JWT, 204, até 30 eventos/minuto; aceita apenas nome do evento e códigos instalado/destino. Não registra usuário, dispositivo, token nem URLs. Esse endpoint fica fora do bloqueio por versão para registrar falhas de clientes antigos.
- Chamadas autenticadas Android abaixo do mínimo retornam 426 com `latestVersionCode`, `latestVersionName`, `minimumSupportedVersionCode` e `updateManifestUrl`. Consumidores web e endpoints públicos permanecem compatíveis. Os headers identificam clientes cooperantes, não substituem autenticação ou garantias contra adulteração.

## Download, integridade e instalação

As classes nativas ficam em `android/app/src/main/kotlin/com/example/apasbac_app/update`:

- `UpdateBridge`: interface Flutter; a Activity somente registra a ponte e informa visibilidade.
- `UpdateStore`: estado persistente, concorrência, recuperação, tentativas e limpeza.
- `UpdateDownloadService`: foreground service `dataSync`, notificação/progresso, timeouts de conexão/leitura, limite total de 15 minutos e wake lock com prazo. Não inicia no boot e para ao concluir, falhar ou cancelar.
- `UpdateVerifier` / `ApkValidation`: tamanho exato, SHA-256 completo, contêiner APK, PackageManager, package, versão, minSdk e conjunto exato de certificados.
- `UpdateInstaller` / `InstallStatusReceiver`: sessão PackageInstaller, permissão de fontes desconhecidas e retorno oficial de confirmação.

O APK é universal, salvo em `files/updates/update.part`, depois renomeado para `update.apk` apenas quando validado. URLs redirecionadas só podem usar HTTPS e hosts GitHub/GitHubusercontent. O download não usa navegador, pasta Downloads nem armazenamento público. Não existe mais de um download/sessão simultâneo.

Downloads continuam ao deixar a tela/colocar o app em segundo plano. Se Android encerrar o processo/serviço, a próxima abertura apresenta uma tentativa interrompida. Um novo download, solicitado pelo usuário, começa do zero; **não reutiliza bytes parciais**. Reinícios manuais sempre verificam o arquivo completo. Após três falhas, a UI apresenta orientação adicional; nenhuma tentativa é automática.

Hash incorreto, tamanho incorreto, APK inválido, package diferente, versão diferente do manifesto, downgrade, minSdk incompatível ou certificado diferente excluem o arquivo. A instalação repete as verificações antes de transferir o arquivo para a sessão. PackageInstaller faz a verificação final de assinatura e compatibilidade de ABI pelo Android. A implementação exige a mesma chave; rotação de certificado não está habilitada.

Em API 31+, é solicitado `USER_ACTION_NOT_REQUIRED` para autoatualização. Android decide se pode dispensar confirmação. Em `STATUS_PENDING_USER_ACTION`, a tela oficial é aberta imediatamente se o aplicativo está visível. Se o usuário deixou o app, as restrições de abertura de Activities em background são respeitadas: é apresentada notificação e a confirmação é retomada ao voltar ao aplicativo. Se a notificação foi negada, voltar ao app ainda permite confirmar.

Antes da instalação, Android 8+ verifica `canRequestPackageInstalls()`. A UI explica e abre diretamente `ACTION_MANAGE_UNKNOWN_APP_SOURCES`; ao voltar, a instalação continua se autorizada. Android 7 (minSdk 24) já suporta PackageInstaller e recebe a confirmação oficial. Não há fallback `file://` nem necessidade de FileProvider para o atualizador. O FileProvider anterior, usado pelas mídias, foi preservado.

O processo pode morrer na substituição. Na próxima abertura, o código instalado confirma o sucesso, apaga os arquivos temporários e limpa o estado. A instalação não desinstala o app, nem apaga login, preferências ou banco. O Android pode exigir abertura manual da nova versão; não há dependência de código executado após a substituição.

O diretório de APKs e o estado nativo de instalação são excluídos de backup/restauração e transferência de dispositivo. Isso evita restaurar uma sessão de instalação de outro aparelho; as demais regras de dados do aplicativo são preservadas.

## Permissões acrescentadas

`ACCESS_NETWORK_STATE`, `REQUEST_INSTALL_PACKAGES`, `UPDATE_PACKAGES_WITHOUT_USER_ACTION`, `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_DATA_SYNC`, `POST_NOTIFICATIONS` e `WAKE_LOCK`.

A autorização de notificações é solicitada só ao primeiro download no Android 13+, e a de instalação só ao instalar. No Android 7, a autorização é global: o app consulta a configuração e abre a tela oficial de segurança; Android 8+ usa autorização por aplicativo. Não há novas permissões de armazenamento. No Android 15+, `onTimeout` encerra o serviço conforme a cota de dataSync; o próprio limite de download é bem menor que essa cota.

**Este APK é para distribuição direta.** Não enviar esse build à Play Store. Uma futura distribuição Play deve ter variant/manifest próprio sem `REQUEST_INSTALL_PACKAGES` e implementar Play In-App Updates por um provider separado; `UpdatePlatform` mantém o transporte/instalador isolado. O canal padrão é `stable`; parser e URL já aceitam `beta` com `--dart-define=UPDATE_CHANNEL=beta`, mas a publicação beta exige seu workflow/política e caminho `update/beta/version.json`.

## Configurar assinatura uma vez

Crie uma chave fora do repositório, com `keytool`, e mantenha backup seguro. Exemplo de comando interativo, sem senha na linha de comando:

```text
keytool -genkeypair -v -keystore /caminho/privado/apasbac-release.jks -alias apasbac -keyalg RSA -keysize 3072 -validity 10000
```

No environment GitHub `android-production`, configure:

- Secrets: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`.
- Variable pública: `ANDROID_SIGNING_CERT_SHA256`, fingerprint SHA-256 do certificado, obtido com `keytool -list -v -keystore ... -alias apasbac`.

O arquivo decodificado fica em `RUNNER_TEMP`, é removido no final e não vira artifact. A chave nunca é gerada a cada release. Nunca publique uma release com assinatura debug. O fingerprint fixado impede uma troca acidental de chave.

Localmente, configure `android/key.properties` (ignorado pelo Git):

```properties
storeFile=C:/caminho/privado/apasbac-release.jks
storePassword=PREENCHER_APENAS_LOCALMENTE
keyAlias=apasbac
keyPassword=PREENCHER_APENAS_LOCALMENTE
```

Ou forneça `ANDROID_KEYSTORE_PATH`, `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD` no ambiente. O Gradle não usa chave debug como fallback de release. Para validar exclusivamente a compilação sem uma chave, existe `APASBAC_ALLOW_UNSIGNED_VALIDATION=true`; o APK resultante é **não distribuível**, e o publicador recusa sua assinatura.

## Publicar a próxima atualização

1. Faça da `source` a branch padrão no GitHub para disponibilizar o workflow manual, se ainda não for. Habilite escrita de contents para Actions e permita ao bot publicar o manifesto nessa branch, conforme a proteção adotada.
2. Edite `pubspec.yaml`, aumentando o inteiro depois de `+`; edite `update/release-notes.json`.
3. Faça commit e push na `source`. Execute **Android stable release** / Run workflow selecionando `source`.
4. O workflow testa/análise → assina/build → testa/lint Android → confere package/versões/certificado → calcula hash/tamanho → cria Release draft com APK → publica Release → baixa anonimamente e valida o asset → grava e commita `update/version.json` na **source**.
5. Instale a primeira versão pelo APK da Release. As seguintes podem usar o atualizador.

O workflow possui exclusão mútua e não substitui APKs de tags já existentes. Um erro antes de publicar o manifesto mantém os clientes na release anterior. Se a Release já foi publicada mas o push do manifesto falhou, após resolver a proteção da branch, baixe o `version.json` anexado àquela Release em `build/release/version.json`, execute `python tool/release.py publish-manifest` e commite somente `update/version.json` na source. O script verifica novamente URL/hash/tamanho e recusa sobrescrever código igual/maior. Alternativamente publique uma versão com código superior.

Hash manual: PowerShell `Get-FileHash -Algorithm SHA256 caminho/app-release.apk` ou Linux `sha256sum app-release.apk`. O fluxo automatizado também confere o APK via `apksigner verify --verbose --print-certs` e `aapt dump badging`.

## Obrigatória e rollback

`mandatory: true` bloqueia qualquer cliente cujo código seja menor que o código daquela release. `minimumSupportedVersionCode: 8` bloqueia códigos abaixo de 8 mesmo com `mandatory: false`, inclusive pela API. Publique o APK antes de elevar o mínimo. Não mantenha um mínimo separado em `.env` ou no backend.

Para desfazer uma versão defeituosa, restaure o comportamento anterior no código e publique **um novo código maior** e tag nova. Exemplo: defeito em 12 → correção em 13. Nunca diminua `versionCode`, reutilize tags ou substitua o APK de uma Release já anunciada.

Se o repositório se tornar privado, o workflow interrompe a publicação. Não acrescente PAT ao aplicativo. Será necessário manter um repositório público dedicado a artefatos/metadados ou implementar proxy autenticado no backend com credenciais somente no servidor; o sistema atual foi implementado para os repositórios públicos auditados.

## Validação local

```text
flutter analyze
flutter test
flutter build apk --debug
cd android
./gradlew :app:testDebugUnitTest :app:lintDebug
cd ..
python -m unittest discover -s tool -p "test_*.py"
```

Na API: `npm ci`, `npm run prisma:generate`, `npm test`, `npm run lint`, `npx nest build`. O script legado `npm run build` também executa seed no banco: para validar somente a compilação, use `npx nest build` depois de gerar Prisma, sem disparar seed em produção.

Testes automatizados usam HTTP/plataforma simulados no Dart e regras de arquivo/identidade reais na JVM. Testes de API validam cache, 426, JSON inválido, proteção contra edição do cache e preservação de metadados no filtro global. O publicador testa progressão de códigos/mínimo e falha de asset. A análise geral pode apresentar infos preexistentes; o workflow usa `--no-fatal-infos` na árvore inteira e análise estrita nos arquivos do atualizador.

Em Windows, se o cache Pub estiver em C: e o projeto em D:, o compilador incremental Kotlin pode falhar ao relativizar caminhos. Execute a validação com `gradlew.bat :app:assembleDebug :app:testDebugUnitTest :app:lintDebug -Pkotlin.incremental=false -Pkotlin.compiler.execution.strategy=in-process --max-workers=2`. Não é necessário mudar a configuração de produção.

Teste final em Android real: instale um APK release assinado, publique um segundo com a mesma chave e código maior, verifique download em background, negação/concessão da permissão, confirmação/cancelamento pelo instalador e preservação da sessão. Repetir em API 24, 26, 31 e 35/36. Para corrupção, use um ambiente de teste com manifesto apontando para um APK cujo hash/package/versão/certificado não corresponda. Não altere o canal stable de produção para esses testes.
