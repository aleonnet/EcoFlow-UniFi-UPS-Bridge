---
status: aceito
---

# Wi‑Fi do River 3 Plus: frente fechada — 2026-09-02

## Contexto e problema

O dono relatou que a sessão anterior "ficou presa em dificuldades e não conseguiu evoluir no
Wi‑Fi". A validação de 2026-09-02 (`2026-09-02-2123-validacao-estado-e-programa-de-frentes.md`)
mostrou que não houve dificuldade de implementação: a pesquisa
`../PESQUISA_ECOFLOW_WIFI_20260901.md` leu por inteiro as dez fontes citadas e concluiu que o
rádio Wi‑Fi do aparelho fala apenas com a nuvem da EcoFlow. O manual oficial define que sem
Internet a comunicação é por Bluetooth; os participantes da discussão do NUT confirmam que o
aparelho não age como servidor na rede. Nenhuma sondagem local foi feita porque não há
protocolo local a sondar. Numa queda de energia, a nuvem depende do próprio roteador que este
projeto se propõe a desligar.

## Opções consideradas

1. Continuar procurando um caminho Wi‑Fi local — nenhuma fonte o descreve; o único integrador
   de rede local conhecido morreu em 2023 cobrindo a geração 1.
2. Nuvem da EcoFlow (Developer API) só para visibilidade — comprovada por terceiros com o
   River 3 Plus; exige conta de desenvolvedor e relaxa a regra de "sem nuvem" apenas para
   telemetria não crítica.
3. BLE local a partir do próprio Mac mini — protocolo revertido por terceiros (`ha-ef-ble`),
   com limites de alcance e de uma conexão por vez.
4. USB ao Mac mini — a única via com driver oficial no NUT (subdriver EcoFlow, presente na
   2.8.5 instalada no mini).

## Decisão

**Fechar a frente Wi‑Fi local** (opção 1) por decisão do dono em 2026-09-02. A via de dados é
USB (opção 4). As opções 2 e 3 viram frentes próprias, abertas amanhã, cada uma com plano e
pré-requisito declarados: conta de desenvolvedor EcoFlow para a nuvem; o River presente e perto
do mini para o BLE.

## Consequências

- Bom: ninguém volta a gastar sessão procurando o que as fontes dizem não existir.
- Ruim: sem o aparelho na bancada, nenhuma via de dados está ativa; o mini segue com o
  simulador.

## Confirmação

Em vigor enquanto `../PESQUISA_ECOFLOW_WIFI_20260901.md` mantiver o veredito "não existe
caminho Wi‑Fi local comprovado"; deixa de valer se uma fonte primária nova mostrar um protocolo
local — então novo arquivo, este marcado `superado por`.
