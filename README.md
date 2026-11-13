# No Dopamine

Aplicativo Flutter para acompanhar o uso de redes sociais no Android, com
seleção de aplicativos, histórico de sessões, análise diária/semanal e previsão
local do uso dos próximos 7 dias.

## Usar o histórico

A navegação inferior tem duas abas: **Uso** e **Previsão**.

1. Toque em **Autorizar acesso de uso**. Na tela do Android, permita o acesso
   para o **No Dopamine** e volte ao aplicativo.
2. Em **Escolher apps**, marque as redes que deseja acompanhar e salve. A lista
   apresenta redes sugeridas instaladas no aparelho. Ative **Mostrar todos os
   aplicativos** para escolher outros apps, inclusive uma rede não sugerida.
3. Alterne entre **Dia** e **Semana**. Use as setas ou toque na data para consultar
   outro período. A semana vai de segunda a domingo, no fuso local do aparelho.
4. Consulte o total, o gráfico por hora/dia, a participação de cada app e os
   registros de início, fim e duração. A lista de registros tem filtro por app
   e carrega mais sessões conforme solicitado.
5. Puxe a tela para atualizar ou use o botão de atualização. O histórico também
   é sincronizado ao abrir o app e ao retornar a ele.

### Origem e limites dos dados

- O acesso usa a API nativa [UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager),
  com permissão de **Acesso de uso** concedida pelo usuário. Nenhum aplicativo
  é selecionado automaticamente.
- Os tempos são reconstruídos dos eventos de atividades em primeiro plano,
  considerando pausas, tela apagada/bloqueada e reinicializações. Atividades
  simultâneas do mesmo app não duplicam seu tempo. Em multi-janela, dois apps
  em primeiro plano podem somar tempo separadamente; o total é a soma dos apps.
- As sessões são recortadas no período consultado, inclusive na meia-noite.
  O gráfico e o ranking usam as mesmas sessões que aparecem nos registros.
- O Android retém eventos detalhados por poucos dias. O app consulta até 30 dias
  para importar o que o sistema ainda disponibiliza e arquiva os eventos dos
  apps selecionados em SQLite, por até **90 dias**. Histórico anterior à seleção
  também pode ser importado quando ainda disponível no Android.
- Intervalos consultados são registrados separadamente por aplicativo. Períodos
  sem cobertura suficiente são identificados como **histórico parcial**, inclusive
  quando o usuário ficou muito tempo sem abrir o app. Uma lacuna não é apresentada
  como certeza de ausência de uso. Não existe serviço de coleta em segundo plano;
  abra o app regularmente para preservar os eventos antes de o Android removê-los.
- Dados e seleção ficam no armazenamento privado do app, com backup desativado.
  Não há envio para servidor nem leitura de mensagens ou conteúdo das redes.
- Esta funcionalidade está implementada para **Android**. Outras plataformas
  apresentam uma mensagem de disponibilidade, sem simular dados de uso.

## Previsão com aprendizado de máquina

Na aba **Previsão**, os mesmos aplicativos selecionados na aba Uso alimentam uma
projeção para **hoje e os próximos 6 dias**, no fuso do aparelho. A tela mostra:

- Total esperado e aumento/redução em horas e percentual em relação aos últimos
  **7 dias completos**, encerrados ontem.
- Comparação com até quatro blocos anteriores de 7 dias. Esses blocos são móveis,
  diferentes das semanas de segunda a domingo usadas no filtro de histórico.
- Previsão e variação de cada aplicativo, distribuição prevista por dia e o
  método escolhido para cada série.
- Quantidade de dias usados e erro médio diário/erro no total em uma semana
  histórica reservada para teste. Esse erro não é uma garantia de precisão futura.

O motor funciona inteiramente no celular, em um isolate para preservar a fluidez
da interface. Não usa chave de API, serviço pago, envio de logs ou modelo de texto.

### Dados e critérios de cálculo

- O conjunto de treinamento contém até **84 dias completos consecutivos**, sempre
  anteriores a hoje e com cobertura para **todos** os aplicativos selecionados.
  A agregação reutiliza as mesmas sessões e regras de recorte do painel de uso.
- O mínimo é **14 dias**, para observar duas vezes cada dia da semana. Antes disso,
  a tela mostra o progresso da base, sem inventar uma previsão. Lacunas interrompem
  a série recente e não são substituídas por zero. Um dia completo sem uso é zero
  válido; um dia sem cobertura não é uma observação.
- Hoje não participa do treinamento nem da avaliação. Seu uso já observado é um
  limite inferior para a previsão de hoje. Valores por app são limitados a zero e
  à duração física do respectivo dia; o total soma os apps, inclusive em multi-janela.
- São ajustadas por app duas regressões **Ridge** com tendência temporal, seis
  indicadores de dia da semana e intercepto. Tempo é medido em semanas, os pesos
  de recência têm meia-vida de 28 dias e o intercepto não recebe penalização efetiva.
  Os pares de penalizações (tendência/dias da semana) são `(0.2, 0.5)` e `(4, 2)`.
- O benchmark repete a última observação do mesmo dia da semana. Em até seis
  simulações semanais, cada ajuste vê somente os dias anteriores ao alvo. A semana
  mais recente fica **fora da seleção de modelo** e mede o erro mostrado na tela.
- Os demais testes escolhem o menor escore: erro absoluto no total semanal mais
  `0.25 × soma dos erros absolutos diários`. Empates favorecem o benchmark simples.
  Quando só existe uma semana de teste, a regressão mais regularizada é a escolha
  inicial predefinida. Depois da avaliação, o método escolhido é ajustado com toda
  a série completa para produzir a projeção atual.
- Bases com menos de 28 dias ou sem comparação entre modelos recebem o rótulo
  **Estimativa inicial**. Erro médio diário acima de 35% da média recente é
  sinalizado como alta variação. Não são apresentados percentuais de confiança
  nem intervalos probabilísticos sem calibração. Base anterior zero não gera
  percentual de crescimento infinito.

Esse desenho usa [regressão regularizada](https://scikit-learn.org/stable/modules/linear_model.html#ridge-regression)
e [avaliação temporal contra métodos de referência](https://otexts.com/fpp3/toolbox.html),
implementadas em Dart para este conjunto pequeno de séries pessoais. Os testes
automatizados incluem tendência, sazonalidade, limites físicos e ausência de
vazamento dos dados de teste/futuro para a escolha do modelo.

## Organização

```text
no-dopamine/
├── .vscode/
│   ├── extensions.json          # Extensões recomendadas.
│   ├── launch.json              # Inicialização pelo F5.
│   └── settings.json            # Formatação de Dart ao salvar.
├── android/                     # Projeto Android gerado pelo Flutter.
├── lib/
│   ├── main.dart                # Ponto de entrada.
│   ├── app/
│   │   ├── app.dart             # Configuração do MaterialApp.
│   │   └── theme/
│   │       └── app_theme.dart   # Tema visual inicial.
│   ├── core/
│   │   ├── platform/            # Reservado para integrações compartilhadas.
│   │   └── widgets/             # Reservado para componentes compartilhados.
│   └── features/
│       ├── home/
│       │   └── presentation/
│       │       └── home_page.dart
│       ├── usage_monitoring/
│       │   ├── data/            # Repositório via canal nativo.
│       │   ├── domain/          # Sessões, cobertura e agregações.
│       │   └── presentation/    # Seleção, painel, gráfico e registros.
│       └── usage_prediction/
│           ├── data/            # Cálculo local fora da thread da interface.
│           ├── domain/          # Base diária, regressão e validação temporal.
│           └── presentation/    # Projeção, comparação e qualidade do modelo.
├── analysis_options.yaml
├── pubspec.lock
├── pubspec.yaml
└── README.md
```

O código nativo fica em
`android/app/src/main/kotlin/com/example/no_dopamine/usage/`.
Os testes de cálculos e fluxos ficam em `test/features/usage_monitoring/` e
`test/features/usage_prediction/`.
Os arquivos `.gitkeep` preservam as pastas reservadas para funcionalidades futuras.

### Responsabilidade das pastas

- `app`: configuração geral do aplicativo, como o tema.
- `core`: código compartilhado por diferentes partes do aplicativo.
- `features`: organização por funcionalidade, para desenvolver cada parte aos poucos.
- `data`: fontes de dados, adaptações para o sistema operacional e
  implementações de repositórios de cada funcionalidade.
- `domain`: modelos e regras de negócio, sem depender das telas.
- `presentation`: telas, componentes e estado de interface.

As dependências são o Flutter, suas traduções oficiais e o SDK de testes do
Flutter. A integração Android usa `MethodChannel` e APIs do sistema, sem plugins
de terceiros para acessar os logs. O projeto requer Flutter **3.47 ou superior**.

## Preparar no VS Code

O ambiente local está configurado com Flutter **3.47.7**, Dart **3.13.5**,
Android SDK **36** e Java **21**. As extensões **Flutter** e **Dart** estão
instaladas, com formatação ao salvar e execução pelo F5.

Os SDKs estão em `~/develop/flutter` e `~/Android/Sdk`. Os caminhos foram
configurados nas preferências do usuário do VS Code e no terminal Zsh. O Java 21
foi selecionado para o Flutter, preservando o Java padrão dos outros projetos.
Em outro computador, siga o [guia oficial de instalação](https://docs.flutter.dev/install/with-vs-code).

1. Abra esta pasta no VS Code, pelo menu **Arquivo > Abrir Pasta**.
2. Se o VS Code já estava aberto durante a instalação, pressione
   **Ctrl+Shift+P** e execute **Developer: Reload Window**. Abra um novo terminal
   integrado para carregar os caminhos dos SDKs.
3. Confira o ambiente:

   ```sh
   flutter doctor -v
   ```

4. Conecte o celular Android por um cabo USB de dados. No celular, ative as
   **Opções do desenvolvedor > Depuração USB** e aceite **Permitir depuração
   USB** para este computador. Verifique se ele aparece como `device`:

   ```sh
   adb devices -l
   flutter devices
   ```

   Se aparecer `unauthorized`, desbloqueie o celular e aceite a autorização de
   depuração. Se não aparecer, verifique o cabo e reconecte o USB. As regras USB
   do Android já estão instaladas no Linux deste computador.

5. Selecione seu celular na barra inferior do VS Code e pressione **F5** com a
   configuração **No Dopamine**. Também é possível iniciar pelo terminal:

   ```sh
   flutter run -d <id-do-celular>
   ```

O resultado esperado é o painel **Seu tempo nas redes**, com o fluxo de permissão
e seleção de aplicativos no primeiro acesso.
Salve um arquivo Dart durante a depuração para aplicar as alterações com hot
reload. Use **Shift+F5** para encerrar. Mantenha o `pubspec.lock` no controle de
versão para registrar as versões usadas pelo aplicativo.

### Android e iOS

O projeto Android e os metadados do Flutter já foram gerados com os modelos
oficiais, preservando os arquivos de `lib/`. O ambiente está preparado para
celular Android por USB, conforme o
[guia oficial para Android](https://docs.flutter.dev/platform-integration/android/setup).
O Android Studio e um emulador não são necessários para essa configuração.

A pasta `ios/` ainda não foi gerada. Gerá-la não permite compilar para iPhone no Linux: para executar e
compilar a versão iOS, será necessário um Mac com Xcode, conforme o
[guia oficial para iOS](https://docs.flutter.dev/platform-integration/ios/setup).

O Flutter permite compartilhar a interface e parte da lógica entre plataformas.
O monitoramento de uso depende das APIs, permissões e restrições de cada sistema.
No Android, a implementação usa
[UsageStatsManager](https://developer.android.com/reference/android/app/usage/UsageStatsManager);
no iOS, são os frameworks
[Device Activity](https://developer.apple.com/documentation/deviceactivity) e
[Family Controls](https://developer.apple.com/documentation/familycontrols).
A integração iOS ainda não foi implementada.

## Conferir o código

Com o Flutter instalado e as dependências obtidas:

```sh
dart format lib test
flutter analyze
flutter test
```

Os testes verificam recorte de sessões, total por app, divisão por hora/dia,
atividades sobrepostas, bloqueio de tela, reinicializações, sessões em andamento,
lacunas, permissão revogada, seleção salva, alternância de períodos, navegação
entre abas, aprendizado de tendências, sazonalidade, validação temporal e base
insuficiente para previsão.

Para compilar um APK de depuração Android ARM64:

```sh
flutter build apk --debug --target-platform android-arm64
```

O APK fica em `build/app/outputs/flutter-apk/app-debug.apk`. A execução por USB
exige um celular conectado e autorizado.
