#!/bin/bash
# river-cabo.sh — quem fala com o River pelo cabo: nós ou o aplicativo da EcoFlow.
#
# A interface de no-break do River é EXCLUSIVA: um leitor por vez (medido em
# 2026-09-04 — com o serviço deles no cabo o nosso driver recebe zero dados; com
# o nosso no cabo, o deles diz "connection failed"). A porta serial do mesmo
# aparelho NÃO é exclusiva, então a leitura de potência continua funcionando dos
# dois lados.
#
#   liberar  — para o nosso leitor; o aplicativo da EcoFlow pode usar o cabo
#   retomar  — devolve o cabo para o nosso serviço
#   estado   — diz quem está com o cabo agora
set -uo pipefail
AGENTE="com.river.nut-driver"
PLIST="$HOME/Library/LaunchAgents/$AGENTE.plist"
UID_ATUAL="$(id -u)"

estado() {
    if pgrep -qf "usbhid-ups -a river-office"; then
        echo "cabo: NOSSO (o serviço está lendo o River)"
    elif pgrep -qf "PowerManagerService"; then
        echo "cabo: LIVRE para o aplicativo da EcoFlow (o serviço dele está no ar)"
    else
        echo "cabo: livre (ninguém lendo pelo padrão de no-break)"
    fi
    if [ -e /dev/cu.usbmodem102 ]; then
        echo "porta serial: presente — a leitura de potência funciona nos dois casos"
    else
        echo "porta serial: ausente — confira o cabo"
    fi
}

case "${1:-estado}" in
    liberar)
        launchctl bootout "gui/$UID_ATUAL/$AGENTE" 2>/dev/null
        sleep 2
        pkill -f "usbhid-ups -a river-office" 2>/dev/null
        echo "[OK] cabo liberado — abra o aplicativo da EcoFlow em modo Local."
        echo "     Enquanto isso o nosso serviço fica sem leitura do no-break."
        estado
        ;;
    retomar)
        [ -f "$PLIST" ] || { echo "[ERRO] não achei $PLIST" >&2; exit 1; }
        # Quem está com o cabo? O driver do aplicativo da EcoFlow roda de dentro
        # do pacote dele; o nosso, do Homebrew. Subir o nosso por cima do deles
        # daria um leitor vivo e MUDO — pior que falhar, porque parece que deu certo.
        if pgrep -qf "PowerManager.*usbhid-ups"; then
            echo "[ERRO] o aplicativo da EcoFlow está com o cabo (modo Local)." >&2
            echo "       Feche o Power Manager, ou mude-o para o modo Remote," >&2
            echo "       e rode 'retomar' de novo." >&2
            exit 3
        fi
        launchctl bootstrap "gui/$UID_ATUAL" "$PLIST" 2>/dev/null
        # Prova real: não basta o processo existir, tem de CHEGAR DADO.
        leitura=""
        for _ in 1 2 3 4 5 6 7 8; do
            sleep 2
            leitura="$(/opt/homebrew/bin/upsc river-office@127.0.0.1 battery.charge 2>/dev/null)"
            [ -n "$leitura" ] && break
        done
        if [ -n "$leitura" ]; then
            echo "[OK] cabo de volta para o nosso serviço — bateria em ${leitura}%."
        else
            echo "[ERRO] o nosso leitor subiu mas não recebeu dado nenhum." >&2
            echo "       Quase sempre é outro programa com o cabo. Feche o Power Manager" >&2
            echo "       e rode 'retomar' de novo; se persistir, desconecte e reconecte o cabo." >&2
            estado
            exit 4
        fi
        estado
        ;;
    estado) estado ;;
    *) echo "uso: river-cabo.sh liberar|retomar|estado" >&2; exit 2 ;;
esac
