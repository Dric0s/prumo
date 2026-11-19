# Prumo

App iOS de frases por período do dia (manhã, tarde, noite e madrugada), com widget na Tela Bloqueada e na Tela de Início. Funciona sem conexão e sem conta. Implementação nativa em SwiftUI + WidgetKit, conforme o plano em `Prumo-plano-de-produto.pdf`.

## Estrutura

```
PrumoKit/                Pacote Swift compartilhado por app e extensão (testável no Linux)
  Sources/PrumoKit/
    Modelo.swift         Tema, Periodo, Frase, Fonte
    Catalogo.swift       Carga e validação do catálogo embarcado (5.000 registros + 45 fontes)
    Tempo.swift          DataCivil, HoraDoDia, Horarios
    Preferencias.swift   Temas, horários, lembretes e validação
    Slots.swift          ChaveSlot, Slot e ResolvedorDePeriodos (Calendar, fuso, horário de verão)
    Selecionador.swift   Baralho por período, alternância de temas, ciclos e leitura de reserva
    Armazenamento.swift  SQLite: preferências, agenda, salvas, interações
    Motor.swift          Fachada: planejar, atualizarPreferencias, salvas, espelho de preferências
    Integracoes.swift    PrumoLink (prumo://frase/<id>), lembretes, timeline do widget, App Group
    Resources/           prumo-catalogo.json e prumo-fontes.json (iguais aos do kit)
  Tests/PrumoKitTests/   47 testes (swift-testing)
App/                     SwiftUI: Hoje, Salvas, Widgets, Ajustes e detalhe da frase
Widget/                  Widget Extension: accessoryRectangular, systemSmall, systemMedium
Compartilhado/           Paleta e utilidades de exibição compiladas nos dois alvos
project.yml              Especificação do XcodeGen (gera Prumo.xcodeproj)
docs/kit/                LEIA-ME, mercado, avaliações e o CSV do catálogo
```

## Como rodar

### Motor (Linux ou macOS)

```sh
cd PrumoKit
swift test
```

No Fedora o SQLite vem de `sqlite-devel`. Os testes cobrem catálogo, viradas de período, horário de verão, os 1.250 dias sem repetição, reconfiguração, mudança de fuso, concorrência entre conexões, leitura de reserva, lembretes, timeline e links.

### App e widget (macOS com Xcode 16 ou posterior)

```sh
brew install xcodegen
xcodegen generate
open Prumo.xcodeproj
```

Antes de rodar no iPhone, ajuste em `project.yml` (ou em Build Settings):

| Ajuste | Valor atual | Observação |
|---|---|---|
| `DEVELOPMENT_TEAM` | vazio | Seu Team ID |
| `PRUMO_BUNDLE_ID` | `br.prumo.app` | A extensão usa `<id>.widget` |
| `PRUMO_APP_GROUP` | `group.br.prumo.app` | Precisa existir no portal Apple Developer, nos dois alvos |

O App Group é lido do `Info.plist` (`PrumoAppGroup`) pelo app e pela extensão, então só existe um lugar para mudar. Se ele não estiver configurado, cada processo usa o próprio Application Support e o widget deixa de enxergar as reservas do app.

### CI

`.github/workflows/ios.yml` roda os testes do motor no Linux e, num runner macOS, gera o projeto e compila app e widget para o simulador sem assinatura. Serve para validar a compilação sem ter um Mac por perto.

## Como funciona

- **Slot**: um período de uma data civil local. A noite que atravessa a meia-noite pertence à data em que começou. Antes do primeiro horário do dia vale a noite da data anterior.
- **Reserva**: `Motor.planejar()` reserva numa transação (`BEGIN IMMEDIATE`) os IDs do slot vigente até sete dias à frente. Índice único por (data, período) entre reservas ativas. Um pedido repetido devolve o mesmo ID, seja do app, do widget ou do aviso.
- **Banco no App Group**: SQLite com journal de rollback (não WAL), para que nenhum lock de arquivo sobreviva a uma transação e o iOS não encerre o processo suspenso (`0xdead10cc`).
- **Seleção**: uma fila por tema e período, em embaralhamento estável (FNV-1a + SplitMix64) com semente local. Alterna os temas ativos que ainda têm frases inéditas no ciclo do período. O ciclo só recomeça quando o conjunto elegível esgota e não repete a última frase na fronteira.
- **Reconfiguração**: mudar temas ou horários mantém slots decorridos e salvas, recicla reservas futuras e, se o tema da frase vigente saiu, reserva outra e guarda a anterior no histórico (`ativo = 0`). Mudar só os lembretes não mexe na agenda.
- **Falhas**: sem acesso ao banco (por exemplo, antes do primeiro desbloqueio), o motor devolve uma leitura de reserva determinística do bundle, sem gravar como vista. As preferências ficam espelhadas em `preferencias.json`, sem proteção de arquivo, para que a reserva respeite temas e horários.
- **Widget**: timeline com a entrada vigente e uma por virada, e renovação em até 12 h (15 min se estiver em reserva). `widgetURL` = `prumo://frase/<id>?origem=widget`. A extensão também pode planejar, então o app fechado não interrompe a troca.
- **Avisos**: `UNCalendarNotificationTrigger` com um ID por slot (`prumo.slot.2026-11-18.tarde`), só para manhã, tarde e noite, com a mesma frase do widget. A permissão é pedida apenas ao ligar os lembretes. Desligar cancela os pedidos pendentes.
- **Medição**: o toque no widget ou no aviso registra uma abertura local. O resumo em Ajustes só sai do aparelho se a pessoa compartilhar.

## Situação em relação ao plano

| Fase | Situação |
|---|---|
| S1 · prova nativa | Projeto com app, extensão e App Group. Falta assinar e instalar no iPhone. |
| S2 · motor offline | Feito e testado: 5.000 registros, baralhos, persistência e relógio injetável. |
| S3 · fluxos e acesso | Quatro telas, salvas com desfazer, guia, estados vazios e textos históricos. Falta o teste com VoiceOver no aparelho e o teste de instalação com oito pessoas. |
| S4 · extensões e avisos | Três famílias, avisos locais e reação à troca de fuso. Falta exercitar duas instâncias do widget no aparelho. |
| S5–8 | Não iniciadas (TestFlight, piloto, ficha da loja). |

O código do app e do widget passou por checagem de sintaxe, mas **ainda não foi compilado contra o SDK do iOS**: o ambiente de desenvolvimento é Fedora. A primeira compilação no Xcode (ou no CI) pode apontar ajustes pequenos.

### Verificar no aparelho (página 13 do plano)

- Viradas 23h59/00h00 e 05h59/06h00, troca de fuso e horário de verão com o mesmo slot mantendo o ID.
- Modo avião com o app fechado: viradas, reinício e leitura antes e depois do primeiro desbloqueio.
- Maiores textos do catálogo no acessório retangular, na menor largura e com texto grande, sem reticências.
- Dois widgets instalados, troca de temas, aviso antigo abrindo o ID correspondente.
- Toque depois da virada: abre o ID que estava na tela, e Hoje mostra o período novo.

O ícone em `App/Assets.xcassets` é provisório, gerado a partir da marca do protótipo.
