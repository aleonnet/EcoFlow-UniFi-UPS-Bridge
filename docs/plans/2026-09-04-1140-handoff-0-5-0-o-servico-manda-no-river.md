# Handoff — 0.5.0: o serviço manda no River

status: superado por 2026-09-05-1727-handoff-0-7-0-driver-do-nut-e-o-disco.md
data: 2026-09-04
supera: 2026-09-04-0140-handoff-0-4-0-e-frente-do-river.md

## 1. O que esta versão entrega

Os três atos que o dono pediu, cada um cercado por confirmação na tela e por trava no serviço:
entregar o River ao aplicativo da EcoFlow (e tomá-lo de volta), mudar o aviso de bateria fraca
do aparelho, e desligar o próprio River. Mais a mudança de fundo que tira a senha do caminho:
**quem cuida do leitor do no-break agora é o nosso serviço**, não o launchd.

O porquê de cada coisa, com as medições, está em
`../decisions/2026-09-04-1130-o-servico-manda-no-river.md`. A lista para quem instala está no
`CHANGELOG.md`, seção `[0.5.0]`.

## 2. O que a revisão fria do diff pegou, e que já está corrigido

Seis bloqueadores, todos com cerca nova no portão:

1. A trava do próprio driver ficava aberta quando o desligamento falhava.
2. As rotas de ação tentavam falar com o aparelho **sem conta de administração** — o instalador
   não criava nenhuma.
3. O serviço morria no pedido de encerramento e deixava os dois processos do no-break órfãos
   **com o cabo**.
4. Leitor que não sobe virava tempestade de processos (sem teto).
5. Gravação no aparelho que não podia ser conferida era mostrada como sucesso.
6. Recusas do River chegavam à tela com a frase errada (ou crua).

Mais quatro acertos menores: o portão passou a comparar o **conteúdo** da configuração do NUT
da máquina (só os nomes escapavam), e ganhou a mesma guarda para o diretório de estado do dono;
cada trava passou a ser chamada pelo próprio nome na recusa; o aviso de bateria fraca ganhou
botão Salvar (antes gravava a cada passo do arrastar); e armar passou a ser recusado enquanto o
cabo estiver emprestado.

## 3. O que ficou fora, declarado

- **Ligar/desligar tomadas** (B35): não existe caminho medido — nem o perfil de no-break nem o
  projeto público do protocolo serial escrevem. Vira frente de pesquisa com bancada sem carga
  crítica.
- **O desligamento REAL do River nunca foi executado** (B42). O botão existe e recusa em todas
  as cercas; a prova de bancada é com o dono presente.
- **Prova de que o aviso de bateria fraca não desliga a saída** (B43): exige descarregar o
  aparelho até o limiar. O que está medido é a descrição do próprio driver — é o nível em que
  ele **avisa**.

## 4. Ler primeiro, ao retomar

1. Este arquivo.
2. `../decisions/2026-09-04-1130-o-servico-manda-no-river.md` — as decisões da 0.5.0.
3. `../decisions/2026-09-04-0110-river-3-plus-o-que-o-cabo-entrega.md` — o aparelho medido.
4. `../reference/api-local.md` — o contrato vivo, com as rotas e recusas novas.
5. `../BACKLOG_20260901.md`, seção B — o que sobrou da frente do River.

## 5. Próximo passo

Instalar no Mac mini (pede a senha de administrador, que é ato do dono) e medir na bancada:
entregar o cabo com o aplicativo da EcoFlow aberto, retomar, gravar o aviso de bateria fraca e
ler de volta. O desligamento real do River, só com ele presente.

```
curl -fsSL https://raw.githubusercontent.com/aleonnet/EcoFlow-UniFi-UPS-Bridge/main/river-bridge-install.sh | bash
```
