# O serviço passa a mandar no River (0.5.0)

status: aceito
data: 2026-09-04
supera: —

Ordem do dono, nas palavras dele: *"são funcionalidades que devem existir e basta cercá-las com
um diálogo (padrão do nosso design system do App) alertando/confirmando a ação"*, mais a
cobrança justa: *"sobre o ssh você sempre executou no mac mini, porque agora quer depender de
mim?"*.

Até a 0.4.1 o serviço só **lia** o River. Esta versão dá a ele três atos — emprestar o cabo,
mudar o aviso de bateria fraca do aparelho e desligar o próprio River — e tira a senha do dono
do caminho do dia a dia.

## 1. Quem cuida do leitor do no-break

**Decisão: o nosso serviço.** Antes eram dois registros do sistema, criados pelo instalador.

Três medições no Mac mini, em 2026-09-04, levaram a isso:

1. Registrados como programa do usuário, não sobem sem alguém logado: o mini reiniciou às
   01h17, ninguém logou, e o River ficou **uma hora sem vigia**.
2. Registrados como serviço do sistema, só o administrador os pausa — e pausar é o que permite
   emprestar o cabo. Isso pediria a senha do dono a cada empréstimo.
3. O pacote do aplicativo da EcoFlow traz `pkill -9 usbhid-ups` e `pkill -9 upsd`, rodados com
   poder de administrador quando ele abre.

Como filhos do nosso serviço, os três problemas somem de uma vez: sobem quando ele sobe (e ele
é do sistema, logo no boot), param e voltam sem senha, e nascem com **nome próprio**
(`river-bridge-ups`, `river-bridge-upsd`), fora da mira daquele `pkill`. O nome próprio é dado
por `exec -a`, que escolhe o nome do processo: medido em 2026-09-04, o processo
aparece como `river-bridge-ups` e o `pkill` pelo nome de fábrica não o alcança.

Duas cercas que a revisão fria exigiu, ambas com defeito plantado no portão:

- **Recuo entre tentativas.** Com o cabo solto, o serviço lançava dois processos a cada volta
  do laço, sem teto. Agora cada falha seguida espera o dobro, até um minuto.
- **Encerramento junto com o serviço.** O pedido de saída do sistema virava morte súbita e os
  dois processos ficavam órfãos **com o cabo**; o serviço seguinte não conseguia abrir o
  aparelho.

## 2. O que o aparelho aceita, medido

```
$ upsrw river-office@127.0.0.1
[battery.charge.low]
Remaining battery level when UPS switches to LB (percent)
Type: STRING    Value: 0

[driver.flag.allow_killpower]
Safety flip-switch to allow the driver daemon to send UPS shutdown command
Type: NUMBER    Value: 0

$ upscmd -l river-office@127.0.0.1
driver.killpower
```

Rodado na máquina do dono em 2026-09-04, com o River ligado (`battery.charge: 98`,
`ups.status: OL`).

O que a nossa proteção usava do aviso de bateria fraca do aparelho saiu junto: até a
0.4.1 havia um alerta na tela comparando esse número com o corte físico configurado,
como se fossem a mesma coisa. Não são — o aparelho não publica o corte físico —, e o
alerta virava acusação falsa justamente agora, que o dono muda esse número pela nossa
tela. Foi removido.

**Uma escrita e um comando. Nada mais.** Ligar e desligar tomadas **não existe** por este
caminho, e não se inventa quadro para um aparelho que alimenta os equipamentos de alguém — o
projeto público do protocolo serial (`greyltc/r3pcomms`, MIT) também **só lê**.

### O que `battery.charge.low` é, e o que não é

É o nível em que o aparelho **avisa** — a descrição acima é do próprio driver, lida no ato. É o
"Low battery reminder" do aplicativo deles. **Não** é o limite físico de descarga (aquele vai
de 0 % a 100 % no aplicativo da EcoFlow e o perfil de no-break não o expõe). Por isso a linha
na tela é editável, e por isso ela se chama "aviso", não "corte". A nossa própria proteção não
depende dele: a configuração do NUT traz `ignorelb`.

## 3. Cercas de cada ato

| Ato | Cercas |
|---|---|
| Emprestar o cabo | confirmação na tela + recusa com qualquer proteção armada (o serviço ficaria sem ver a queda) |
| Desligar o River | trava `RIVER_POWEROFF_ALLOWED`, que **só muda no arquivo do serviço** + recusa com qualquer proteção armada + confirmação nomeando o que será cortado + a trava do próprio driver aberta pelo tempo do comando e fechada num `finally` |
| Aviso de bateria fraca | botão Salvar (não grava a cada passo do arrastar) + conferência lendo de volta; não conseguir conferir é falha, não sucesso |
| Armar qualquer proteção | recusado enquanto o cabo estiver emprestado — a leitura antiga ainda parece boa por alguns segundos. **Desarmar continua sempre aceito** |

## 4. A conta que manda no aparelho

O servidor do no-break separa quem lê de quem manda. A conta que o aplicativo da EcoFlow usa
(`powermanager`) é `upsmon secondary` de propósito: acompanha e **não** consegue mandar o River
desligar. A conta do serviço (`riverbridge`) nasce na instalação, com senha aleatória, e a
senha mora em dois lugares que têm de concordar: a conta no servidor e um arquivo 0600 do
diretório de estado. Fora do arquivo de configuração de propósito — a tela lê esse arquivo
inteiro.

## 5. Fora desta versão, declarado

**Ligar e desligar tomadas.** Não existe caminho medido: nem o perfil de no-break nem o projeto
público do protocolo serial escrevem. Vira pesquisa com protocolo próprio — bancada sem carga
crítica, comparação com o aplicativo deles, e só então implementação.
