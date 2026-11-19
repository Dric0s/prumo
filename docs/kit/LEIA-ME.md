# Prumo

Pesquisa, protótipo e catálogo da primeira versão de um app iOS de frases por período. Prumo é o nome de trabalho.

## Arquivos

| Arquivo | Uso |
|---|---|
| Prumo-plano-de-produto.pdf | Pesquisa de mercado, decisões de UX, fontes editoriais, implementação iOS e evolução até o TestFlight. |
| Prumo-prototipo.html | Abra o arquivo em um navegador para experimentar Hoje, Salvas, Widgets e Ajustes. A demonstração contém 16 frases do catálogo e guarda preferências no navegador. |
| prumo-catalogo.json | Fonte de conteúdo para o app e a extensão. JSON UTF-8, sem dependência de rede. |
| prumo-catalogo.csv | Os mesmos 5.000 registros para filtragem e revisão. CSV UTF-8 com BOM, separado por ponto e vírgula. |
| prumo-fontes.json | Referências com título, URL, classe e nota sobre o conteúdo consultado. As referências LIN01 e LIN02 informam a linha editorial geral. |
| prumo-avaliacoes.csv | 42 resenhas da App Store, com loja, data exibida, tom, tema principal, paráfrase e URL. Usa o mesmo formato do catálogo CSV. |
| prumo-mercado.md | Matriz de concorrentes, contagens por tema, exemplos e metodologia. |

## Catálogo em português do Brasil

| Objetivo | Manhã | Tarde | Noite | Madrugada | Total |
|---|---:|---:|---:|---:|---:|
| Estudos | 313 | 313 | 312 | 312 | 1.250 |
| Trabalho | 312 | 313 | 313 | 312 | 1.250 |
| Empreendedorismo | 312 | 312 | 313 | 313 | 1.250 |
| Academia | 313 | 312 | 312 | 313 | 1.250 |
| **Total** | **1.250** | **1.250** | **1.250** | **1.250** | **5.000** |

O catálogo contém 4.968 mensagens editoriais, 30 trechos históricos em tradução própria e dois trechos originalmente em português. Há 1.008 mensagens editoriais com uma influência específica referenciada. As 649 leituras cujo texto difere da versão curta incluem complementos ou versões de tamanho diferente. Em cada registro, as duas versões expressam a mesma ideia.

### Contrato de integração

O JSON tem `schema_version` (inteiro), `catalog_version` (texto), `locale` (texto) e `frases` (lista). No CSV vazio corresponde a `null` nos campos opcionais.

| Campo do registro | Significado |
|---|---|
| `id` | Identificador persistente, como `pr-00001`. Favoritos, agenda, widget e notificações usam esse ID. Em revisões de texto, conservar o ID e incrementar a versão do catálogo. |
| `tema` | `estudos`, `trabalho`, `empreender` ou `treino`. |
| `periodo` | `manha`, `tarde`, `noite` ou `madrugada`. |
| `curta` | Texto para a Tela Bloqueada e o widget pequeno. O maior tem 64 caracteres. Validar a largura renderizada no iPhone. |
| `texto` | Texto para Hoje ou para a versão média, com até 162 caracteres. Quando necessário, o widget médio usa `curta`. |
| `tipo` | `editorial`, `citacao_traduzida` ou `citacao_em_portugues`. |
| `fonte_id` | Chave opcional para `id` em `prumo-fontes.json`. Para um texto editorial, indica influência conceitual. |
| `autor`, `obra`, `localizador`, `contexto` | Presentes nos 32 trechos históricos. Exibir a autoria e a obra na leitura e abrir o contexto sob demanda. |

### Rotação local

1. Embarcar a mesma versão do JSON nos recursos do app e da Widget Extension. Usar `Codable` e indexar por ID e por combinação de tema e período. Embarcar também as referências se o app exibir fonte e contexto.
2. Resolver o slot pela data civil do início daquele período no fuso local. Os horários iniciais são 00h, 06h, 12h e 18h. O sistema recebe uma entrada antecipada por virada e decide quando exibi-la.
3. Usar o App Group para compartilhar preferências, reservas futuras e histórico. Proteger a gravação com transação e chave única por data de início e período. Uma reserva futura bloqueia o mesmo ID no horizonte. Se for invalidada por nova preferência, reciclar a reserva enquanto preserva os registros passados. Manter separados os slots programados e as ações observadas.
4. Alternar entre os temas habilitados que ainda têm frases inéditas no período. Manter o histórico por período ao mudar de filtro. Com preferências estáveis, renovar o ciclo só quando o conjunto elegível esgotar e evitar a repetição imediata na fronteira. Ao tocar no widget ou no aviso, abrir o ID que estava associado ao texto exibido.
5. Preparar a janela futura com o mesmo seletor para telas, widget e avisos. Caso o contêiner compartilhado fique temporariamente indisponível, o bundle traz a leitura de reserva. Usar período e tema conhecidos quando possível. A primeira instalação, preferências e lembretes devem funcionar em modo avião.

### Verificações da entrega

- Contagem de 5.000 IDs únicos e matriz de 16 combinações.
- Comparação de frases curtas e longas entre registros após remover acentos, pontuação e espaços e uniformizar maiúsculas. Uma mesma frase pode aparecer nos dois campos do próprio registro.
- Revisão de pares de versões curtas com maior semelhança textual. A verificação de utilidade e tom com o público integra o piloto.
- Validação de todas as chaves de referência e dos campos de atribuição. Os textos traduzidos registram a edição consultada nas notas das fontes históricas.
- Testes do protótipo para quatro telas, salvas, desfazer, filtros, formatos, validação de horários, viradas e larguras de 320, 390 e 768 px. Layout final da extensão, instalação e pontualidade são critérios em iPhone físico.
