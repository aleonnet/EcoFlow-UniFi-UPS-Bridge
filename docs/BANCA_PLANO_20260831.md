# Banca adversarial do plano de execução — registro de vereditos (2026-08-31)

Plano avaliado: plano de execução do projeto (bridge + Componente D UI nativa),
elaborado em sessão de 2026-08-31. Processo: 3 lentes adversariais instruídas a
REFUTAR, iteração até APROVA.

## Rodada 1 — REPROVA nas 3 lentes

- **L1 (semântica de plataforma):** 1 GRAVE — semântica do launchd `KeepAlive`
  afirmada sem dicionário declarado, contraditória com a cerca de bind, e race entre
  resposta 202 e exit; 2 MÉDIOS — "SSE reconecta sozinho" é propriedade do EventSource
  de browser, não da plataforma Apple; premissa de sessão de login do LaunchAgent
  `gui/$uid` não declarada; 3 MENORES (os.replace intra-volume; porta sem critério;
  `swift test` não executa XCUITest).
- **L2 (aderência e escopo):** 1 GRAVE — ciclo de dependência entre a instalação
  guiada (UI-4) e o instalador da Fase 6; 2 MÉDIOS — PoC UniFi sem depender de fonte
  NUT real (risco de telemetria sintética contra §24/§11); cláusula Keychain da §15
  não confrontada; 7 MENORES.
- **L3 (executabilidade):** 1 GRAVE — mesmo ciclo; 7 MÉDIOS — API local com dois
  donos; acesso admin ao UDR7 não declarado; disponibilidade do RIVER sem status;
  HA sem ordem/gate; gates não mecânicos; rollback ausente por etapa; Fases 3–5
  colapsadas sob um único gate; 3 MENORES.

## v2 — correções aplicadas

Ciclo desfeito (Fase 6 dividida; UI-4 reposicionada), contrato de relançamento
launchd especificado (`KeepAlive={SuccessfulExit: false}` + 3 comportamentos),
dependências reais e rollback por ordem, gates mecânicos, API local com dono único,
Keychain confrontado com racional, telemetria sintética vetada contra UDR7 real.

## Rodada 2 — REPROVA estreita

27/27 achados da rodada 1 conferidos FECHADOS, com citação linha a linha. Porém:
1 contradição nova MÉDIA (N1 — a explicitação das dependências do hardening criou
deadlock no ramo "relatório de inviabilidade", desfecho que o §24 aceita) e 4 MENORES
(N2 — emenda §15 registrava 1 de 3 exceções; N3 — decisão Gatekeeper sem casa no
sequenciamento; N4 — rollback da Fase 1 prometia manifesto que ainda não existia;
N5 — gate do instalador cobria 1 dos 3 comportamentos de relançamento).

## v3 — correções aplicadas

Ramo de inviabilidade cancela Fases 4–5 e destrava o hardening; as 3 exceções §15 na
emenda; Gatekeeper ancorado na ordem do instalador; Fase 1 usa lista de artefatos
registrada em disco no ato (embrião do manifesto); gate do instalador prova os 3
comportamentos.

## Rodada 3 — APROVA

N1–N5 confirmados fechados; varredura de vizinhança sem contradição nova. Observação
cosmética absorvida na emenda da spec (racional do TLS dispensado junto às demais
exceções §15 — feito).

## VEREDITO FINAL: APROVA (v3)

Plano submetido ao dono na v3 e aprovado em 2026-08-31.
