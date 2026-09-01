#!/usr/bin/env python3
"""Cerca da mancha de backdrop (2026-08-31): reprova a captura se existir uma
banda sustentada (>=5% da altura) SEM texto, na metade inferior, mais que 6
níveis de luminância mais escura que o rodapé vazio — a assinatura da união
de backdrops do Liquid Glass sobre a coluna de conteúdo.
A captura DEVE ser de janela com FOCO (sem foco o Glass não renderiza o
backdrop pleno e a validação é nula) — use tools/captura-focada.sh.
Uso: checa_mancha.py captura.png"""
import sys
from PIL import Image

img = Image.open(sys.argv[1]).convert("RGBA")
alpha = img.getchannel("A")
# bbox do OPACO (>=250): o bbox simples inclui a SOMBRA (alpha parcial).
opaco = alpha.point(lambda a: 255 if a >= 250 else 0)
bbox = opaco.getbbox()
if not bbox:
    print("captura vazia"); sys.exit(2)
x0, y0, x1, y1 = bbox
rgb = img.convert("RGB")
h = y1 - y0
LIMIAR = 6.0
JANELA = max(int(h * 0.05), 20)

pior = 0.0
for gx in (x0 + 30, (x0 + x1) // 2):
    col = [sum(rgb.getpixel((gx, y))) / 3 for y in range(y0, y1)]
    rodape = col[int(h * 0.88):int(h * 0.95)]
    ref = sum(rodape) / len(rodape)
    for inicio in range(int(h * 0.50), int(h * 0.85) - JANELA, JANELA // 2):
        banda = col[inicio:inicio + JANELA]
        if min(banda) < 150:      # texto/controle na banda: não é mancha
            continue
        delta = ref - sum(banda) / len(banda)
        pior = max(pior, delta)
print(f"pior_banda={pior:.1f} (limiar {LIMIAR})")
sys.exit(1 if pior > LIMIAR else 0)
