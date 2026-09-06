---
status: proposto
data: 2026-09-06
frente: B39 — o segundo River por Bluetooth (plano `../plans/2026-09-06-1800-o-segundo-river-por-bluetooth-0-11-0.md`)
---

# O rádio Bluetooth é lido pela sessão do usuário (filho do River Bridge), nunca pelo serviço

## Contexto

O River da sala não tem cabo no Mac mini. A única porta local dele é o Bluetooth (o protocolo V2 da EcoFlow,
decifrado pela comunidade em `rabits/ha-ef-ble`). O serviço da ponte roda como **root, sem sessão gráfica**
(é um serviço de sistema registrado pelo `SMAppService`). A dúvida que a B39 deixou em aberto era se o serviço
poderia ler o rádio diretamente.

## Medições (2026-09-06, 17h20–17h55; comandos no *Impact sweep* do plano)

1. **Por ssh no Mac mini** (processo sem app responsável na sessão gráfica), o Python do pacote com `bleak`:
   `BleakBluetoothNotAvailableError: Bluetooth is not authorized … DENIED_BY_UNKNOWN`.
2. **Nesta máquina, como filho de um app mínimo** assinado com Developer ID e com `NSBluetoothAlwaysUsageDescription`,
   aberto por `open`: a varredura de 8 s devolveu `rc=0` e 23 aparelhos. O consentimento é atribuído ao
   **processo responsável** — o app —, e o filho o herda.
3. **O mesmo app-prova na sessão gráfica do mini** ficou parado esperando o diálogo de consentimento (ninguém
   na tela para permitir). É o comportamento esperado: o macOS pergunta uma vez, em nome do app.
4. O Python do pacote tem *hardened runtime* com validação de biblioteca: rodas do PyPI (`_objc.cpython-313-darwin.so`)
   **só carregam depois de reassinadas** com o nosso Developer ID (`different Team IDs`), que é o que o
   empacotador já faz com todo Mach-O de `libs/`.

## Decisão

O leitor Bluetooth é um **processo filho do River Bridge** (o programa, na sessão do usuário): o interpretador
Python do pacote rodando `river_unifi_bridge.ble_leitor`, com a biblioteca `eflib` embutida. O app supervisiona
(sobe, relança com recuo, encerra ao sair) e ganha a chave `NSBluetoothAlwaysUsageDescription`. **A verdade
continua no serviço**: o filho pergunta ao serviço quem ler (`GET /v1/ble`) e devolve as leituras
(`PUT /v1/ble/rivers/{id}/leitura`); o serviço publica na tela, nos eventos e no NUT.

## Consequências

- O River da sala só é lido enquanto o programa está aberto na sessão do dono. Programa fechado → 30 s depois
  o serviço marca `sem_leitura` e o NUT recebe `DATASTALE`. É dito na tela; não é falha escondida.
- O diálogo de Bluetooth aparece **uma vez**, em nome do River Bridge, e só quando há um River ativo com conta
  (o filho não toca o rádio antes disso).
- A proteção (desligar o UDR7) **não** lê o River da sala: continua lendo o leitor de fábrica do escritório.
- Rejeitado: Swift/CoreBluetooth no próprio app — reescreveria ECDH, cifra e 19 famílias de protobuf que a
  `eflib` já tem testadas. Rejeitado: o serviço lendo o rádio — medição 1.
