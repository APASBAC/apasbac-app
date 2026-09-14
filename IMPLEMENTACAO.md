# Atualização do aplicativo

Adicione a logo em `assets/images/apasbac_logo.png`. O asset está registrado no
pubspec; até a inclusão da imagem será exibido um ícone provisório.

Na Administração, o botão `+` abre Novo animal e Novo monitoramento. A aba
Configurações carrega `/configs` e permite editar contato e intervalo dos
monitoramentos. Novos monitoramentos usam o tutor vinculado ao animal adotado.

Uploads usam `/storage/signed-upload`, encaminham `form_fields` por multipart
diretamente ao `upload_url` do Cloudinary, com um cliente HTTP separado sem JWT,
e enviam `secure_url` à API como `photoUrls` ou `imageUrls` e `videoUrl`.
Não é necessário configurar segredo do Cloudinary no app.
Referência: https://cloudinary.com/documentation/client_side_uploading

O formulário de monitoramento preserva a regra já existente de um vídeo e cinco
fotos. A API permite reenvio nos estados PENDING e REJECTED; a interface consulta
o estado antes do upload. A revisão permite APPROVED/REJECTED a partir de IN_REVIEW
por meio do campo booleano `approved`.

Foram consultadas as respostas reais de login, configurações, animais,
monitoramentos e assinatura de upload. Os schemas CreateAnimalDto e
SubmitMonitoringDto da documentação fornecida estão vazios; o cadastro usa
os campos de animal observados e `photoUrls` descrito na documentação, e o
envio usa `imageUrls` e `videoUrl` observados nos registros. O backend precisa
aceitar e validar esses campos. A regra de cinco fotos e vídeo foi preservada
do aplicativo, pois não está descrita nesses schemas.

Verificação: `flutter test` (HTTP simulado, sem cadastrar dados em produção) e
`flutter analyze --no-fatal-infos`. Os testes cobrem payloads, validação, campos
assinados, isolamento do JWT e falhas de upload. Um envio completo em dispositivo
com imagens reais ainda deve ser validado contra o backend/Cloudinary.
