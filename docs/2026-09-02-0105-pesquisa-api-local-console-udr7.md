---
status: proposto
---

# A API local do console desliga o UDR7? — pesquisa, 2026-09-02

Supera `2026-09-01-2243-pesquisa-ssh-sota-udr7.md`, cuja conclusão **"API para SABER, SSH
para AGIR"** está errada. O erro não foi de raciocínio: aquela pesquisa testou a chave do
Site Manager (nuvem) e a API de integração do Network, e **nunca** testou a superfície que a
própria interface do console usa quando alguém está logado nele. É nessa superfície que está
o desligamento.

## Gramática de evidência

`[P]` primária · `[S]` secundária (wiki, gist, blog — **nunca vira `[P]` por repetição**) ·
`[M]` medido no ato, com o comando registrado ·
**`[P-estático]`** leitura do código do fabricante **sem execução** — marca nova, criada
porque a versão anterior desta frente apresentou leitura de código como se fosse medição.
`[P-estático]` **não** é `[M]` e nunca autoriza dizer "funciona".

---

## 1. O que foi medido no console (`192.168.1.1`, UDR7)

Comandos `curl` rodados em 2026-09-02, sem sessão autenticada:

| Chamada | Resultado | Grau |
|---|---|---|
| `GET /api/system` | **200** — `{"hardware":{"shortname":"UDR7"},"name":"Dream Router 7"}` | `[M]` |
| `GET /api/system/info` · `/api/firmware` · `/api/users/self` · `/api/system/poweroff` | **401** | `[M]` |
| `GET /api/system/rota-que-nao-existe` | **401** | `[M]` |
| `OPTIONS` em `/api/system/poweroff`, `/api/system/reboot`, `/api/nada` | **204**, mesmo `Allow` em todos | `[M]` |

**Conclusão medida, e ela restringe o desenho:** sem sessão autenticada **não existe forma de
distinguir uma rota que existe de uma que não existe** neste console. Tudo que não é público
responde 401, e `OPTIONS` responde 204 para qualquer caminho. Portanto qualquer prova de
alcance **tem de ser autenticada**, e `GET /api/system` — que responde 200 sem autenticação —
**não serve como prova de nada**.

## 2. O que foi lido no código da interface do console

7,3 MB de bundles baixados do próprio aparelho do dono (`/main~0…js`, `/main~2…js`,
`/275…js`, `/905…js`, `/989…js`). Tudo abaixo é `[P-estático]`: é o código do fabricante,
lido, **não executado**.

| Achado | Trecho |
|---|---|
| O botão **Shut Down** chama a rota de desligamento | `N("/api/system/poweroff",{method:"POST"})` em `ConsoleControlsSettings` |
| Rota irmã de reinício | `/api/system/reboot` |
| Autenticação local | `login:"/api/auth/login"`, `refreshSession:"/api/auth/refresh"`, `logout:"/api/auth/logout"`, `self:"/api/users/self"` |
| Corpo do login | `{username, password, token, rememberMe}` — `token` é o segundo fator |
| Sessão | cookie (`credentials:"include"`) + header `X-CSRF-Token` (`addCSRF`/`updateCSRF`) |
| Autorização é **granular** | mapa de flags: `{"edit:os-settings:restart":false, "edit:os-settings:poweroff":false, "edit:os-settings:ssh":false, "edit:os-settings:reset":false, …}` |
| Rotas de sistema existentes | `/api/system`, `/poweroff`, `/reboot`, `/reset`, `/ssh/setpassword`, `/syslog/*`, `/updates/channels` |

### 2.1 O UniFi OS do UDR7 não sabe o que é um UPS

Varredura de "UPS" nos 7,3 MB: as **únicas** ocorrências são links de catálogo da loja
(`/ups`, `/ups2u`, `/ups-tower-us`, `/ups-2u-eu`). Não há tela, estado, rota ou evento de UPS
no sistema operacional do console. `[P-estático]`

## 3. O que fecha portas (para não serem reabertas)

| Fato | Grau | Fonte |
|---|---|---|
| A UPS da Ubiquiti é **servidor** NUT para terceiros — o fluxo suportado é o inverso do nosso | `[P]` | ui.com/integrations/power-tech/ups-solutions |
| **O UDR7 não tem porta USB alguma** (4× 2.5 GbE, 1× SFP+) → o River nunca plugará no console | `[P]` | techspecs.ui.com/unifi/cloud-gateways/udr7 |
| `upsmon` secundário conecta no `upsd` remoto e invoca o `SHUTDOWNCMD` **local** no evento crítico | `[P]` | man page oficial do NUT |
| `unifi-common` (on_boot.d) lista `udr7` entre os modelos e persiste via overlay em `/data/on_boot.d` | `[P]` | `remote_install.sh`; issue #660 fechada pelo PR #672 (firmware 4.1.18) |
| Pedido de cliente NUT nativo no UniFi OS: fechado como "não planejado" | `[S]` | issue #528 do unifios-utilities |

**O Mac como servidor NUT não é limitação do nosso desenho — é a única topologia possível.**

## 4. Correção de registro

A versão anterior afirmou que a URL da issue #528 respondia 404 e retirou a fonte. A issue
**existe** (o repositório foi renomeado para `unifi-common`, e a URL antiga resolve). Ela
continua sendo `[S]` e continua sem promover nada: fechada como "não planejado" é ausência de
recurso, não prova de impossibilidade.

## 5. Conclusão

1. **SSH não é o único caminho, e não é o melhor.** Existe uma rota local de desligamento,
   com autorização granular própria, no mesmo aparelho e sem nuvem no meio.
2. **Nada disso foi executado.** A rota é `[P-estático]`. Ela só vira `[M]` quando alguém
   rodar contra o console e a saída entrar no runbook. Enquanto isso, dizer "consigo
   desligar" é invenção.
3. **O que continua faltando é o mesmo de ontem: a prova.** Trocar SSH por HTTP não conserta
   o defeito central — o daemon arma sem nunca ter falado com o console. A prova de alcance
   tem de ser autenticada (§1) e tem de verificar a permissão de desligar da própria sessão,
   e ainda assim ela prova **autorização**, não **execução**.

## 6. Premissas declaradas, NÃO medidas

- Que a interface permita criar uma conta só com `edit:os-settings:poweroff`. O mapa de
  flags existe; que o editor de contas o exponha item a item é suposição. **O desenho não
  pode depender disso para ser seguro.**
- Segundo fator obrigatório para administradores.
- Política de bloqueio por tentativas de login malsucedidas.
- Comportamento do certificado do console em atualização de firmware (uma fixação de
  certificado precisa de origem e de política de rotação definidas antes de existir).

## Fontes

- Interface do console do dono, bundles baixados de `https://192.168.1.1/` — `[P-estático]`
- Soluções de UPS da Ubiquiti — <https://ui.com/integrations/power-tech/ups-solutions>
- Especificações do UDR7 — <https://techspecs.ui.com/unifi/cloud-gateways/udr7>
- `upsmon` (NUT, manual oficial) — <https://networkupstools.org/docs/man/upsmon.html>
- `unifi-common`, suporte a `udr7` — <https://github.com/unifi-utilities/unifi-common>
- Suporte ao UDR7 no On Boot 2.x, issue #660 — <https://github.com/unifi-utilities/unifi-common/issues/660>
- Cliente NUT no UniFi OS, issue #528 (`[S]`) — <https://github.com/unifi-utilities/unifios-utilities/issues/528>
