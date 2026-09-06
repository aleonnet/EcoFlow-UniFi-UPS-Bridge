# Revisão fria do plano da 0.10.0 (o widget do macOS)

status: aceito
data: 2026-09-06
plano: `2026-09-06-1500-o-widget-do-macos-0-10-0.md`

Revisor: agente `cold-reviewer` (Roadworthy), só leitura; duas rodadas.

## Rodada 1 — REJECTED (cinco bloqueadores, todos de levantamento meu)

- **B1** — o widget do Dropover, usado como referência de Developer ID, é assinatura da **App Store** (`Authority=Apple Mac OS Application Signing`). Correção: a referência passou a ser a minha própria prova (`prova-widget.sh`: pacote Developer ID + appex mínimo, registrado no `pluginkit`); a notarização só se prova na release.
- **B2** — a gravação do retrato em `TelemetryStore.apply` escreveria no contêiner real do dono durante `swift test` e em cada cópia de mutação (14 testes constroem o store). Correção: destino injetado no `init`, `nil` por padrão.
- **B3** — "medido" onde era inferência (o ad-hoc). Correção: o registro ad-hoc foi medido (registra); o acesso ao contêiner ficou declarado como inferência.
- **B4** — a conta do orçamento de recargas (piso de 15 min no app = 96/dia; isenção de "primeiro plano" não medida para app de barra de menu; `.after` é ele mesmo um pedido). Correção: sem piso no app; periódico só na linha do tempo, `.after(30 min)` = 48/dia; isenção fora da conta; `recargas.log` para medir no mini.
- **B5** — Info.plist do appex com três chaves, contra onze nas referências. Correção: as onze, versão = a do app, `LSMinimumSystemVersion 26.0`; provas por `PlistBuddy`.

Avisos W1–W6 incorporados: Team ID único com prova no empacotador; `.onChange(of: prefs.language)`; gravação só quando o retrato muda; diálogo do Sequoia como observável na bancada; `phase.didSet` com `oldValue`; âncoras literais das cenas.

Classe do que faltou: verificar a autoridade da assinatura da referência e os consumidores de `TelemetryStore(` antes de escrever "medido"/"hook".

## Rodada 2 — REJECTED com um bloqueador (5 → 1), mecânico

- A seção de mudanças ainda trazia `deveRecarregar(anterior:novo:ultimaRecarga:agora:)`, o relógio que a rodada 1 tirou. Corrigido no ato.
- Avisos: o mutante da S76 trocava o `guard` e não compilaria — passa a trocar o `return` final; a prova do Team ID só com identidade de verdade. Notas: linhas `:85`/`:151`; saídas das provas guardadas (`prova-widget.out`, `prova-widget-adhoc.out`, `grupo-min.out`).

Contagem de bloqueadores caiu; aplicado sem terceira rodada (regra 5 da casa). Aprovação do dono em 2026-09-06: "Aprovo, execute".
