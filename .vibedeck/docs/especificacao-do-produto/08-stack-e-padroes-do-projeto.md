---
author: ai
---
# 08 — Stack e padrões do projeto

# Stack e padrões cadastrados para orientar a refatoração

Levantamento em 22/10/2026 via MCP list_stack e list_patterns. Fonte de verdade: [vibedeck.json](../../../vibedeck.json) e os tópicos de regras vinculados. Esta é uma fotografia do cadastro; consultar novamente as ferramentas antes de implementar.

## Resumo

7 tecnologias, 21 padrões e 57 regras vinculadas (48 must e 9 should).
Todos os padrões consultados têm paths vazio: hoje seus tópicos são globais. Não há nota de uso específica nos padrões retornados. O cadastro não comprova que o código atual já cumpra todas as regras.

## Stack registrada

As notas abaixo foram copiadas do cadastro. A última coluna contextualiza a migração sem alterar o registro.

| Tecnologia | Categoria cadastrada | Autoria | Nota de uso cadastrada | Leitura para a migração |
| --- | --- | --- | --- | --- |
| Swift | language | ai | Swift 6.2 / SwiftPM; app em SwiftUI (Liquid Glass, macOS 26), CLI com swift-argument-parser e MCP com o swift-sdk | Nota descreve a implementação atual; o destino do Core/CLI/MCP é Rust. Interface macOS continua como cliente. |
| Apple | os | ai | App nativo macOS 26; o CLI/MCP também compila em Linux | Plataforma do app atual. O cadastro não prova validação de uma distribuição multiplataforma. |
| Cloudflare Workers | cloud | ai | worker/ serve os JSON Schemas (schema/v1 é a fonte) | Infraestrutura dos schemas. Remover sessões de nuvem não implica remover esse worker. |
| TypeScript | language | ai | worker/ serve os JSON Schemas (schema/v1 é a fonte) | Associado ao worker de schemas pela nota cadastrada. |
| Rust | language | human | Sem nota cadastrada | Cadastrado pelo usuário e confirmado para o futuro Core/CLI/MCP; versão e layout dos crates ainda a definir. |
| MCP | backend | human | Sem nota cadastrada | Cadastrado pelo usuário; já é interface do produto e continua na migração, local e via SSH. |
| Zod | frontend | human | Sem nota cadastrada | Cadastrado pelo usuário sem nota de uso. Papel, versão e componente de integração ainda precisam ser definidos. |

A categoria cloud de Cloudflare Workers corresponde ao serviço de schemas, não à feature de sessões de nuvem cuja remoção foi pedida. Não remover essa infraestrutura apenas pelo nome da categoria.
Rust, MCP e Zod foram cadastrados pelo usuário sem notas; a finalidade de Rust/MCP está documentada nas decisões, mas o uso concreto de Zod permanece pendente. Não introduzir um runtime TypeScript no Core Rust apenas pela presença de Zod na stack.

## Padrões registrados e tópicos

| TDD | Test-Driven Development: o teste vem antes do código; cada comportamento novo nasce de um teste que falha. | Global (paths vazio) | [padrao-tdd](../../rules/padrao-tdd.json) |
| SOLID | Responsabilidade única, aberto/fechado, substituição de Liskov, segregação de interfaces e inversão de dependência. | Global (paths vazio) | [padrao-solid](../../rules/padrao-solid.json) |
| Injeção de dependência | Os objetos recebem suas dependências de fora (construtor/parâmetro) em vez de criá-las ou buscá-las em singletons. | Global (paths vazio) | [padrao-injecao-de-dependencia](../../rules/padrao-injecao-de-dependencia.json) |
| Núcleo funcional | Functional core, imperative shell: lógica em funções puras e dados imutáveis; efeitos colaterais só na borda. | Global (paths vazio) | [padrao-nucleo-funcional](../../rules/padrao-nucleo-funcional.json) |
| Clean Code | Código legível: nomes que revelam intenção, funções pequenas, sem duplicação nem código morto. | Global (paths vazio) | [padrao-clean-code](../../rules/padrao-clean-code.json) |
| Desenvolvimento orientado a comportamento | Comportamentos esperados são descritos em cenários com contexto, ação e resultado observável. | Global (paths vazio) | [padrao-desenvolvimento-orientado-a-comportamento](../../rules/padrao-desenvolvimento-orientado-a-comportamento.json) |
| Design por contrato | Operações declaram precondições e pós-condições; objetos preservam invariantes durante suas mudanças. | Global (paths vazio) | [padrao-design-por-contrato](../../rules/padrao-design-por-contrato.json) |
| Clean Architecture | Camadas concêntricas (entidades, casos de uso, adaptadores, frameworks) com dependências apontando só para dentro. | Global (paths vazio) | [padrao-clean-architecture](../../rules/padrao-clean-architecture.json) |
| DDD | Domain-Driven Design: o código usa a linguagem do negócio, com entidades, objetos de valor, agregados e contextos delimitados. | Global (paths vazio) | [padrao-ddd](../../rules/padrao-ddd.json) |
| Repository | O domínio acessa a persistência por repositórios com interface de coleção, sem conhecer o banco. | Global (paths vazio) | [padrao-repository](../../rules/padrao-repository.json) |
| Serviço de domínio | Uma operação de negócio que não pertence a uma única entidade ou objeto de valor é expressa como serviço de domínio. | Global (paths vazio) | [padrao-servico-de-dominio](../../rules/padrao-servico-de-dominio.json) |
| Objeto de valor | Um conceito de domínio é definido por seus atributos, sem identidade própria, com valores imutáveis e invariantes protegidas. | Global (paths vazio) | [padrao-objeto-de-valor](../../rules/padrao-objeto-de-valor.json) |
| Strategy | Algoritmos intercambiáveis atrás de uma interface comum, escolhidos em tempo de execução em vez de if/switch espalhados. | Global (paths vazio) | [padrao-strategy](../../rules/padrao-strategy.json) |
| Factory | Centraliza a criação de objetos (Factory Method / Abstract Factory), escondendo qual tipo concreto é instanciado. | Global (paths vazio) | [padrao-factory](../../rules/padrao-factory.json) |
| Builder | Constrói objetos complexos passo a passo, separando a construção da representação final. | Global (paths vazio) | [padrao-builder](../../rules/padrao-builder.json) |
| Adapter | Converte a interface de um componente existente na interface que o cliente espera. | Global (paths vazio) | [padrao-adapter](../../rules/padrao-adapter.json) |
| Decorator | Acrescenta comportamento a um objeto envolvendo-o em outro com a mesma interface, sem herança. | Global (paths vazio) | [padrao-decorator](../../rules/padrao-decorator.json) |
| Observer | Um sujeito notifica observadores interessados sem conhecê-los, desacoplando quem emite de quem reage. | Global (paths vazio) | [padrao-observer](../../rules/padrao-observer.json) |
| Command | Encapsula uma ação como objeto, permitindo enfileirar, registrar, repetir e desfazer. | Global (paths vazio) | [padrao-command](../../rules/padrao-command.json) |
| State | O comportamento de um objeto muda conforme seu estado interno, modelado como tipos ou casos explícitos. | Global (paths vazio) | [padrao-state](../../rules/padrao-state.json) |
| Singleton | Uma única instância compartilhada. Use com parcimônia: prefira injetar a instância. | Global (paths vazio) | [padrao-singleton](../../rules/padrao-singleton.json) |

## Aplicação proposta ao Core — interpretação para revisar na etapa 01

- **Clean Architecture, SOLID e injeção de dependência:** domínio e casos de uso independentes da UI, transporte MCP, filesystem, SSH e providers. Instâncias concretas são montadas nas entradas da aplicação.
- **DDD, objetos de valor e serviços de domínio:** usar os conceitos do VibeDeck; proteger invariantes de ideias, regras, revisões e execuções. Serviços de domínio tratam operações entre conceitos, sem reter estado de negócio entre chamadas.
- **Núcleo funcional:** decisões determinísticas com valores explícitos; persistência, relógio e processos nas bordas. DDD pode proteger invariantes em funções/métodos puros; não exige I/O dentro das entidades.
- **Repository e Adapter:** persistência e integrações entram por contratos do domínio/aplicação; adaptadores traduzem formatos e chamadas. Repository não exige introduzir banco de dados.
- **Strategy, Factory e Builder:** organizar variantes reais e montagem complexa. Não criar tipos artificiais só para demonstrar todos os padrões em cada funcionalidade; cumprir os gatilhos das regras cadastradas.
- **Command, State e Observer:** ações com histórico/desfazer, estados/transições e notificações com cancelamento explícito. O padrão Command não é sinônimo do registro de prompt “comando” do VibeDeck.
- **Decorator:** comportamento transversal por composição, preservando contrato e sem esconder mudança de permissões, retries ou efeitos.
- **Singleton:** quando houver instância única, acesso na composição e distribuição por injeção, com concorrência segura. O padrão cadastrado não exige criar estado global.
- **TDD, BDD, design por contrato e Clean Code:** cenários observáveis orientam testes; operações têm entradas/garantias/invariantes explícitas; regressões são verificadas e o código mantém nomes e responsabilidades claros.

Esse mapa não muda globs, severidades ou regras. Se um padrão precisar de escopo específico ou conflitar com outra exigência, propor e registrar a mudança no VibeDeck antes da implementação afetada.

## Verificação na refatoração

1. Reler stack, padrões e regras aplicáveis aos arquivos e ao item de revisão.
2. No plano, relacionar os padrões relevantes às responsabilidades e fronteiras da mudança.
3. Criar/executar testes correspondentes ao comportamento novo/corrigido e à paridade da migração. Invariantes puras não precisam de infraestrutura real; integrações têm verificações próprias.
4. Rodar checks obrigatórios. Regras manuais seguem o fluxo do projeto: não viram pass porque o nome do padrão foi citado.
5. Nas revisões arquiteturais solicitadas, registrar evidências concretas de dependências, composição, estados, persistência e testes. Contagens de padrões ou classes não provam conformidade.

## Decisões a fechar

- Registrar papel e versão do Zod, ou revisar seu cadastro se não fizer parte da solução escolhida.
- Atualizar notas de Rust/MCP e distinguir notas históricas de Swift das escolhas para o futuro.
- Decidir se os 21 padrões devem continuar globais ou receber globs/notas por domínio, adaptadores e UI.
- Definir módulos/crates, contratos e testes que comprovem as fronteiras. Não presumir que cada padrão exige um crate.
- Manter as decisões recentes: início guiado, Docs por symlink e execução somente local/SSH. Esta anotação não reintroduz sessões de nuvem.

## Regras cadastradas — texto e verificação

Transcrição do retorno do MCP com IDs e severidades para rastreabilidade; tópicos vinculados continuam sendo a fonte vigente.

### TDD

ID do padrão: `tdd`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Todo comportamento novo ou corrigido tem um teste automatizado** (`3787FB4C-952B-493D-8421-453F8A269983`)

  Escreva primeiro o teste que falha (vermelho), depois o mínimo de código para passar (verde), depois refatore.
  Verificar: a alteração vem acompanhada de testes que a exercitam; um bug corrigido ganha um teste de regressão.

- **must — A suíte de testes passa antes de concluir** (`91C694F5-E503-40B4-8948-F36AB26CE509`)

  Verificar: rode os testes do projeto e confirme que todos passam; não desative nem apague testes para fazer passar.

- **must — O código é testável sem infraestrutura real** (`F3088591-7653-4C64-A34A-3D73F1BBE3ED`)

  Dependências externas (rede, disco, relógio, banco) entram por parâmetro ou protocolo e são trocadas por dublês nos testes.
  Verificar: os testes novos não dependem de serviços externos nem de estado global.

### SOLID

ID do padrão: `solid`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Cada tipo tem uma única responsabilidade** (`8C7BA779-881A-41CF-8EE4-0BD757A1F484`)

  Verificar: classes/structs/módulos novos ou alterados têm um motivo só para mudar; nada de "Manager" que faz tudo.

- **must — Módulos de alto nível dependem de abstrações, não de implementações concretas** (`51430D46-BC6E-4046-9210-858637F8D59B`)

  Verificar: regras de negócio recebem protocolos/interfaces; implementações concretas são injetadas de fora.

- **should — Interfaces são pequenas e específicas** (`DB2C12A3-2725-43DB-A17C-9188CE7DDCA8`)

  Verificar: nenhum protocolo novo obriga quem o implementa a métodos que não usa.

- **should — Comportamento novo entra por extensão, não alterando código estável** (`C3D4B64B-6478-457F-8E01-693E0376518A`)

  Verificar: prefira novos tipos/estratégias a encher de `if`/`switch` um fluxo existente.

### Injeção de dependência

ID do padrão: `dependency-injection`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Dependências entram pelo construtor ou por parâmetro** (`353A15FA-E289-40E7-A60E-254932382357`)

  Verificar: código novo não instancia serviços concretos internamente nem acessa singletons/estado global para obtê-los.

- **must — A montagem das dependências fica num ponto de composição** (`6E0E61B4-7D1A-4AAA-BAEE-E6AB67857746`)

  Verificar: a criação dos objetos concretos fica no ponto de entrada (main, app, container), não espalhada pelo domínio.

### Núcleo funcional

ID do padrão: `functional-core`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — A lógica de negócio fica em funções puras** (`148F5306-7A09-4435-B513-19A02DED2769`)

  Mesma entrada, mesma saída, sem I/O, relógio ou aleatoriedade escondidos.
  Verificar: regras novas podem ser testadas sem mocks, só com valores.

- **must — Dados são imutáveis por padrão** (`0F92EC73-F142-46BB-B71D-0B5FA45995EE`)

  Verificar: prefira `let`/valores/cópias com alteração a estado mutável compartilhado.

- **must — Efeitos colaterais ficam na casca, fora do núcleo** (`5E97F54A-5E96-455E-AFC5-DFFBEE902029`)

  Verificar: I/O, persistência e chamadas externas ficam nas bordas, que chamam o núcleo puro.

### Clean Code

ID do padrão: `clean-code`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **should — Funções são pequenas e fazem uma coisa** (`8341AA2D-A545-4E2F-9208-4417C95CCF80`)

  Verificar: funções novas cabem na tela e têm um nível de abstração; extraia passos com nomes claros.

- **must — Nomes revelam intenção** (`A9C179E4-D02D-4655-8094-6BC1EEFFB06E`)

  Verificar: variáveis, funções e tipos dizem o que são/fazem, sem abreviações obscuras.

- **must — Sem duplicação nem código morto** (`3644D2EF-AB49-4398-A704-2ADA0729E11E`)

  Verificar: reaproveite o que já existe em vez de copiar; remova código comentado e não usado.

### Desenvolvimento orientado a comportamento

ID do padrão: `bdd`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Cenários descrevem comportamentos observáveis** (`97D0E684-2DDC-48A8-9EEA-EF46C197ADF2`)

  Verificar: inspecione os cenários e confirme que seus resultados descrevem efeitos percebidos pelo usuário ou sistema consumidor, sem depender de detalhes internos.

- **must — Cada cenário explicita contexto, ação e resultado esperado** (`372F0A93-09B7-4BA1-8C56-E752864D5C04`)

  Verificar: confirme que cada cenário identifica suas condições iniciais, a ação executada e o resultado que deve ser observado.

- **should — Cenários de comportamento têm testes automatizados** (`1DCCB47A-35C7-4FF1-94E8-6F30CA1AD380`)

  Verificar: execute os testes correspondentes aos cenários e confira que suas asserções verificam os resultados esperados.

### Design por contrato

ID do padrão: `design-by-contract`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Operações explicitam suas precondições** (`CF6CECEC-501A-47A5-A90E-07BDFB196A9E`)

  Verificar: inspecione o contrato de cada operação e identifique as condições exigidas para suas entradas e estado inicial.

- **must — Operações explicitam suas pós-condições** (`141A0450-CBB3-40C4-A6B3-F4261D66CAE1`)

  Verificar: inspecione o contrato de cada operação e identifique as garantias de saída e estado final para entradas válidas.

- **must — Alterações preservam as invariantes do objeto** (`DD3AC98A-2326-44A7-BDE8-2D8C47B8E97F`)

  Verificar: confira os caminhos de alteração de estado e verifique que nenhum estado público resultante viola as invariantes declaradas.

- **should — Contratos têm testes de entradas válidas e violações** (`C86E132C-C8A2-4A39-AD07-0724ADBBCC67`)

  Verificar: execute testes das precondições, pós-condições e invariantes, incluindo entradas que violam o contrato.

### Clean Architecture

ID do padrão: `clean-architecture`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Dependências apontam só para dentro** (`8229EEC1-E218-4B92-B871-B45798D4FF2B`)

  Entidades ← casos de uso ← adaptadores ← frameworks.
  Verificar: nenhuma camada interna importa ou conhece uma externa.

- **must — Cada caso de uso é uma unidade explícita** (`9E0D5726-189C-476A-9B9A-CD74BED2537B`)

  Verificar: regras de aplicação novas ficam em casos de uso (interactors) com entrada e saída definidas, não em controllers/views.

- **should — Dados atravessam fronteiras como estruturas simples** (`C579A40B-72C8-4CC0-B7FD-025552B6793F`)

  Verificar: entidades e modelos de framework (ORM, DTO de rede) não vazam entre camadas; há mapeamento na fronteira.

### DDD

ID do padrão: `ddd`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — O código usa a linguagem ubíqua do domínio** (`6F6AD706-8212-4EC4-B926-AB5B328AA92E`)

  Verificar: tipos, métodos e eventos têm os nomes que o negócio usa, não nomes técnicos genéricos.

- **must — Regras de negócio vivem nas entidades e objetos de valor, não em serviços anêmicos** (`5A9EA105-6677-402C-93E7-0B20A583FC5B`)

  Verificar: invariantes são garantidas dentro do próprio modelo; nada de entidade só com getters/setters.

- **must — Agregados protegem suas invariantes e são alterados só pela raiz** (`8FA77DB0-01C5-445E-8EED-FAFC0FD37B5E`)

  Verificar: código externo não altera entidades internas de um agregado diretamente; referências entre agregados são por id.

- **should — Contextos delimitados não se misturam** (`D57E5BC7-C217-43A4-BF8A-167F69548656`)

  Verificar: conceitos de um contexto não são importados direto em outro; há tradução (anticorrupção) na fronteira.

### Repository

ID do padrão: `repository`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Acesso a dados passa por repositórios** (`1769AF58-655A-42AC-9E29-A7140F2E6343`)

  Verificar: código de domínio/aplicação não faz SQL, chamadas de ORM ou de arquivo direto.

- **must — A interface do repositório é do domínio; a implementação é da infraestrutura** (`B81CF5E0-6D17-49CC-930B-23F20E32110C`)

  Verificar: o protocolo fica junto do domínio e fala em entidades; a implementação concreta fica fora e pode ser trocada em testes.

### Serviço de domínio

ID do padrão: `domain-service`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Operações do serviço expressam regras que não pertencem a uma única entidade ou objeto de valor** (`62C7B35D-18DE-4E78-AC63-E99E762D6B70`)

  Verificar: inspecione as operações e identifique a regra de negócio e os conceitos de domínio que precisam participar de sua execução.

- **must — Serviços de domínio não mantêm estado de negócio entre chamadas** (`BA09B967-4A58-4966-88B4-AC825568FCA7`)

  Verificar: inspecione os atributos e confirme que os dados de uma execução não são retidos como estado de negócio para a próxima.

- **must — Dependências de infraestrutura entram por abstrações** (`643EF822-1A1D-4CF1-8C9B-52015EF9AEB0`)

  Verificar: inspecione as dependências e confirme que persistência e integrações são acessadas por contratos, sem implementação concreta embutida no serviço.

- **should — Serviços de domínio têm testes das regras de negócio** (`D30A3518-E10A-4D60-AA43-8AFFBE0C8B9E`)

  Verificar: execute testes das operações com valores de domínio e dublês das dependências externas.

### Objeto de valor

ID do padrão: `value-object`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Igualdade de objetos de valor depende de seus atributos** (`F5931FF3-9994-4567-8285-8E3581964795`)

  Verificar: inspecione a comparação de igualdade e confirme que valores com os mesmos atributos são iguais independentemente da instância.

- **must — Objetos de valor são imutáveis** (`8C457638-D3F2-4611-B3E1-4041235542F0`)

  Verificar: confira que não há operação pública que altere os atributos de uma instância após sua criação.

- **must — A construção rejeita valores que violam invariantes** (`579FA025-AA73-45E3-AE4F-F788681E382D`)

  Verificar: inspecione os caminhos de criação e confirme que entradas inválidas são rejeitadas antes de disponibilizar a instância.

- **should — Objetos de valor têm testes de igualdade e invariantes** (`40FDBE88-D79D-45A4-872E-BCDD3FC88FF3`)

  Verificar: execute testes de igualdade entre instâncias e de rejeição de atributos inválidos.

### Strategy

ID do padrão: `strategy`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Variações de comportamento viram implementações de um protocolo** (`602C35DA-8055-4C89-85C1-9829A9F8F10C`)

  Verificar: não há cadeias de if/switch por tipo repetidas em vários pontos; cada variante é um tipo que implementa a mesma interface.

- **must — O cliente depende do protocolo, não da implementação concreta** (`82BDE968-F8CD-4900-95D1-98324D423D61`)

  Verificar: quem usa a estratégia recebe o protocolo por parâmetro ou injeção.

### Factory

ID do padrão: `factory`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — A criação de variantes passa por uma fábrica** (`8966FED8-7577-475E-AA72-C934AE70CD19`)

  Verificar: o código cliente não escolhe o tipo concreto com if/switch; pede à fábrica.

- **must — A fábrica devolve o protocolo/tipo abstrato** (`0A12C92C-88E8-488B-B172-9CE56D7CDE0F`)

  Verificar: o tipo de retorno é abstrato, para o cliente não depender da classe concreta.

### Builder

ID do padrão: `builder`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Objetos com muitos parâmetros opcionais são montados por um builder** (`533F55F2-6E59-48F8-8BB4-42E9CB5773CD`)

  Verificar: não há inicializadores com longas listas de parâmetros opcionais; a montagem é encadeada e legível.

- **must — O resultado do builder é válido ou a construção falha** (`F8DA6028-19D7-4155-BCCF-42EDFD3D0B63`)

  Verificar: build() valida invariantes e não devolve objeto parcial.

### Adapter

ID do padrão: `adapter`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Código de terceiros/legado é isolado por um adapter** (`3B5E424F-9EB4-4F47-BBE0-5C4B234F3FEE`)

  Verificar: o resto do código usa a interface do projeto, não a API externa diretamente.

- **must — O adapter só traduz, sem regra de negócio** (`1B2FEBD0-0380-4A6A-8F73-7F3FD7C7DCDC`)

  Verificar: o adapter converte formatos e chamadas; a lógica de domínio fica fora dele.

### Decorator

ID do padrão: `decorator`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Comportamento transversal é adicionado por composição** (`A9946E0D-A246-4F70-BAAE-CD1B888E5230`)

  Verificar: log, cache, retry etc. envolvem o objeto original com o mesmo protocolo em vez de subclasses ou flags.

- **must — O decorator preserva o contrato do objeto decorado** (`1F7E4A91-438B-4F28-864B-F5B167E7972B`)

  Verificar: mesma interface e mesma semântica; quem usa não distingue o decorado do original.

### Observer

ID do padrão: `observer`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — O emissor não conhece os observadores concretos** (`810BEAF7-23AE-4201-BE49-CA2F33289958`)

  Verificar: o emissor expõe inscrição/cancelamento (callback, AsyncStream, Combine, delegate) e não referencia tipos de quem reage.

- **must — Toda inscrição tem cancelamento claro** (`229A8236-DD0B-4A8B-92F4-796C4426A415`)

  Verificar: observadores são removidos ao fim do ciclo de vida, sem vazar memória nem retain cycles.

### Command

ID do padrão: `command`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Ações de usuário/sistema passíveis de fila, histórico ou desfazer são objetos de comando** (`A9793900-3951-4F0D-9C91-4E95002E7733`)

  Verificar: a ação tem um tipo próprio com tudo que precisa para executar (e desfazer, se aplicável).

- **must — Quem dispara o comando não conhece quem o executa** (`4194F8B5-4564-41DF-94C0-3296FEB8E7D0`)

  Verificar: invoker e receiver ficam desacoplados pelo protocolo do comando.

### State

ID do padrão: `state`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Estados e transições são explícitos** (`67F0BC9B-0056-44EA-9ED5-59CBCE2808C0`)

  Verificar: existe um enum/tipo por estado e as transições válidas ficam em um só lugar, sem flags booleanas combinadas.

- **must — Transições inválidas são impossíveis ou rejeitadas** (`E1379E64-D8BF-4A8C-87BC-2F1C4399B33A`)

  Verificar: o código não permite ir para um estado não previsto; há teste das transições.

### Singleton

ID do padrão: `singleton`. Autoria: `human`. Nota de uso: não informada no cadastro.
Escopo registrado: global, sem globs.

- **must — Singletons não são acessados diretamente por quem os usa** (`7EAC2E11-DF02-43F1-AF7C-4655EA63FC50`)

  Verificar: o acesso ao singleton acontece na composição (raiz da app) e chega aos demais por injeção de dependência.

- **must — O estado compartilhado é seguro para concorrência** (`9F05E489-D53C-4D98-81E5-7172DB35EEC1`)

  Verificar: acesso protegido (actor, lock ou imutabilidade).
