#!/usr/bin/env python3
"""
gera-logo.py — gera o logo do River Bridge para a abertura do instalador.

A fonte é o ÍCONE REAL do app: roda tools/app-icon-render.swift (o mesmo render
que produz o AppIcon.icns), recorta **o escudo** (não o quadrado arredondado), o
reduz com o `sips` do macOS e o cola num canvas com MARGEM px de vazio em volta.
A margem não é enfeite: `halo()` só cria pixels em volta do que está dentro do
canvas e `contorno()` exige vizinho de fora — onde a máscara encosta na borda,
halo e traço somem (é o "cortando ao redor" que o dono viu em 2026-09-01).

O BMP é lido com a biblioteca padrão (sem PIL). Meio-bloco: cada célula do
terminal vira DOIS pixels (topo = frente do "▀", base = fundo), cada pixel com a
SUA cor de verdade — não uma paleta de classes.

Classes por pixel (LG_MASK):
    .  fora (margem, e todo pixel alcançável a partir da borda)
    s  escudo (branco)      r  raio (o vazado do escudo, brilha no batimento)

Saem também, em vetores paralelos (índice = y*LG_W + x quando é por pixel):
    LG_RGB              "r;g;b" de cada pixel (fora = "0;0;0")
    LG_TX/LG_TY         contorno do escudo, ordenado por posição de ARCO
                        (índice = posição: o traço desenha e retrai por arco)
    LG_AX/LG_AY/LG_AOX/LG_AOY/LG_ADL  partículas da constelação: destino,
                        origem fora do canvas (radial com giro de 40°) e atraso
                        — construção de baixo para cima, determinística
    LG_HX/LG_HY         o halo: pixels de fora encostados no escudo (o anel
                        que acende a cada batida do coração)

    ./tools/gera-logo.py            imprime o fragmento bash
    ./tools/gera-logo.py --preview  desenha no terminal (truecolor) para conferir
    ./tools/gera-logo.py --medir    os números, incluindo o produto do orçamento
    ALTURA=40 por padrão (20 linhas: o maior que cabe com o título em 24 linhas);
    MARGEM=2. `ALTURA` tem de ser par — o render lê `mask[y+1]`.
"""
import math, os, struct, subprocess, sys, tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ALTURA = int(os.environ.get("ALTURA", "40"))
MARGEM = int(os.environ.get("MARGEM", "2"))
A_DUR = 8                    # quadros de voo de cada partícula
SONDA = 256                  # resolução da sonda onde o bbox do escudo é medido
BRANCO = 150                 # min(r,g,b) a partir do qual o pixel é escudo
OPACO = 96                   # alpha a partir do qual o pixel conta


def _bbox_do_escudo(dados):
    """Caixa (y0, x0, h, w) do escudo branco na sonda."""
    img = ler_bmp(dados)
    pts = [(y, x) for y, linha in enumerate(img) for x, (r, g, b, a) in enumerate(linha)
           if a >= OPACO and min(r, g, b) >= BRANCO]
    assert pts, "bbox vazio: o escudo não foi encontrado na sonda"
    ys = [p[0] for p in pts]; xs = [p[1] for p in pts]
    return min(ys), min(xs), max(ys) - min(ys) + 1, max(xs) - min(xs) + 1


def renderizar_bmp(altura: int, margem: int) -> tuple[bytes, int, int, int]:
    """Ícone real → bbox do escudo → recorte → resize. Devolve (bmp, largura do
    canvas, altura, margem).

    O BMP sai com o escudo SÓ — quem cola no canvas com a margem é `com_margem`,
    antes de `classificar`; é a margem que faz o halo e o contorno existirem
    (sem ela, quem encosta na borda fica sem vizinho de fora). `sips` opera IN PLACE
    quando não recebe `--out` — por isso a sonda vai para outro arquivo.
    Ordem dos argumentos medida em `man sips`: `--cropToHeightWidth pixelsH
    pixelsW`, `--cropOffset offsetY offsetX`, `--resampleHeightWidth pixelsH
    pixelsW` — ALTURA antes de LARGURA, Y antes de X.
    """
    assert altura % 2 == 0, f"ALTURA tem de ser par (é {altura}): o render lê mask[y+1]"
    work = tempfile.mkdtemp(prefix="gera-logo.")
    master = os.path.join(work, "master.png")
    subprocess.run(["swift", os.path.join(RAIZ, "tools", "app-icon-render.swift"), master],
                   check=True, stdout=subprocess.DEVNULL)
    saida = subprocess.run(["sips", "-g", "pixelWidth", master], check=True,
                           capture_output=True, text=True).stdout
    px_master = int(saida.strip().rsplit(":", 1)[1])   # o AppKit renderiza em retina (2048)

    sonda = os.path.join(work, "sonda.bmp")
    subprocess.run(["sips", "-z", str(SONDA), str(SONDA), "-s", "format", "bmp",
                    master, "--out", sonda], check=True, stdout=subprocess.DEVNULL)
    y0, x0, h, w = _bbox_do_escudo(open(sonda, "rb").read())
    k = px_master / SONDA                              # sonda → pixels do master
    cy, cx, ch, cw = round(y0 * k), round(x0 * k), round(h * k), round(w * k)

    escudo_h = altura - 2 * margem
    escudo_w = max(1, round(escudo_h * cw / ch))
    subprocess.run(["sips", "--cropOffset", str(cy), str(cx), "-c", str(ch), str(cw), master],
                   check=True, stdout=subprocess.DEVNULL)
    bmp = os.path.join(work, "escudo.bmp")
    subprocess.run(["sips", "-z", str(escudo_h), str(escudo_w), "-s", "format", "bmp",
                    master, "--out", bmp], check=True, stdout=subprocess.DEVNULL)
    return open(bmp, "rb").read(), escudo_w + 2 * margem, altura, margem


def ler_bmp(dados):
    """BMP sem compressão ou BI_BITFIELDS, 24/32 bpp, top-down ou bottom-up → [[(r,g,b,a)]]."""
    off = struct.unpack_from("<I", dados, 10)[0]
    w, h = struct.unpack_from("<ii", dados, 18)
    bpp = struct.unpack_from("<H", dados, 28)[0]
    comp = struct.unpack_from("<I", dados, 30)[0]
    assert bpp in (24, 32) and comp in (0, 3), f"BMP inesperado: {bpp} bpp, compressão {comp}"
    topo_para_baixo = h < 0
    h = abs(h)
    passo = bpp // 8
    linha_bytes = (w * passo + 3) // 4 * 4
    img = []
    for y in range(h):
        yy = y if topo_para_baixo else h - 1 - y
        base = off + yy * linha_bytes
        linha = []
        for x in range(w):
            p = base + x * passo
            b, g, r = dados[p], dados[p + 1], dados[p + 2]
            a = dados[p + 3] if passo == 4 else 255
            linha.append((r, g, b, a))
        img.append(linha)
    return img


def com_margem(img, largura, altura, margem):
    """Cola o escudo reduzido num canvas transparente de largura×altura."""
    assert len(img[0]) == largura - 2 * margem and len(img) == altura - 2 * margem, (
        f"o sips devolveu {len(img[0])}×{len(img)}, esperado "
        f"{largura - 2 * margem}×{altura - 2 * margem}")
    vazio = (0, 0, 0, 0)
    canvas = [[vazio] * largura for _ in range(altura)]
    for y, linha in enumerate(img):
        for x, px in enumerate(linha):
            cy, cx = y + margem, x + margem
            if 0 <= cy < altura and 0 <= cx < largura:
                canvas[cy][cx] = px
    return canvas


def classificar(img):
    """'.' fora · 's' escudo · 'r' o vazado do escudo.

    O recorte retangular traz, nos cantos, pixels opacos do gradiente do fundo do
    ícone e a borda anti-aliased do escudo (min < BRANCO). A regra que os elimina:
    **todo pixel não-'s' alcançável a partir da borda do canvas é '.'**; só o não
    alcançável (fechado pelo escudo) é o raio. Efeito declarado: a borda
    anti-aliased vira '.', o escudo encolhe menos de 1 px.
    """
    W, H = len(img[0]), len(img)
    rgb, mask = [], []
    for y in range(H):
        linha = []
        for x in range(W):
            r, g, b, a = img[y][x]
            if a < OPACO:
                linha.append("."); rgb.append((0, 0, 0)); continue
            # borda semi-transparente: compõe sobre preto (terminal escuro)
            r, g, b = r * a // 255, g * a // 255, b * a // 255
            rgb.append((r, g, b))
            linha.append("s" if min(r, g, b) >= BRANCO else "?")
        mask.append(linha)

    fora = [[False] * W for _ in range(H)]
    pilha = [(x, y) for x in range(W) for y in (0, H - 1)] + [(x, y) for y in range(H) for x in (0, W - 1)]
    while pilha:
        x, y = pilha.pop()
        if not (0 <= x < W and 0 <= y < H) or fora[y][x] or mask[y][x] == "s":
            continue
        fora[y][x] = True
        pilha.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    for y in range(H):
        for x in range(W):
            if mask[y][x] == "?":
                if fora[y][x]:
                    mask[y][x] = "."
                    rgb[y * W + x] = (0, 0, 0)
                else:
                    mask[y][x] = "r"
    return rgb, ["".join(l) for l in mask], fora


def conferir(mask):
    """As duas cercas do gerador — rodam em TODA invocação, não só em --medir."""
    classes = set("".join(mask))
    assert classes <= {".", "s", "r"}, f"máscara com classe inesperada: {sorted(classes)}"
    assert any("s" in l for l in mask), "máscara sem escudo — o recorte não achou nada"
    assert set(mask[0]) == {"."} and set(mask[-1]) == {"."}, "borda horizontal não vazia"
    assert all(l[0] == "." and l[-1] == "." for l in mask), "borda vertical não vazia"


def contorno(mask, fora):
    """Pixels 's' com um vizinho-4 em 'fora' (contorno EXTERNO, não o do raio),
    ordenados por ângulo em volta do centroide — começa na ponta de baixo e sobe
    pela esquerda, como o traço do molde da casa."""
    W, H = len(mask[0]), len(mask)
    pts = []
    for y in range(H):
        for x in range(W):
            if mask[y][x] != "s":
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < W and 0 <= ny < H and fora[ny][nx]:
                    pts.append((x, y)); break
    mx = sum(p[0] for p in pts) / len(pts)
    my = sum(p[1] for p in pts) / len(pts)
    pts.sort(key=lambda p: (math.atan2(p[1] + 0.5 - my, p[0] + 0.5 - mx) - math.pi / 2) % (2 * math.pi))
    return pts


def particulas(mask):
    """Cada pixel do escudo ganha origem radial (giro de 40°) e atraso de baixo
    para cima — o mesmo desenho do gerador do haos-install; determinístico.
    `raio` usa max(W, H) porque o canvas não é quadrado: 0,9·max é sempre maior
    que a meia-diagonal, logo toda origem nasce fora da tela."""
    W, H = len(mask[0]), len(mask)
    cx0, cy0 = W / 2.0, H / 2.0
    fora_da_tela = max(W, H) * 0.9
    ys = [y for y in range(H) for x in range(W) if mask[y][x] in "sr"]
    y_base = max(ys)
    saida, i = [], 0
    for y in range(H):
        for x in range(W):
            if mask[y][x] not in "sr":
                continue
            ang = math.atan2(y + 0.5 - cy0, x + 0.5 - cx0) + math.radians(40)
            raio = fora_da_tela + (i % 9)
            saida.append((x, y, int(cx0 + math.cos(ang) * raio), int(cy0 + math.sin(ang) * raio),
                          (y_base - y) // 2 + (i % 3)))
            i += 1
    return saida


def halo(mask):
    W, H = len(mask[0]), len(mask)
    pts = []
    for y in range(H):
        for x in range(W):
            if mask[y][x] != ".":
                continue
            for dx in (-1, 0, 1):
                for dy in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < W and 0 <= ny < H and mask[ny][nx] != ".":
                        pts.append((x, y)); break
                else:
                    continue
                break
    return pts


def vetor(nome, valores):
    return f"{nome}=({' '.join(str(v) for v in valores)})"


def main():
    dados, largura, altura, margem = renderizar_bmp(ALTURA, MARGEM)
    img = com_margem(ler_bmp(dados), largura, altura, margem)
    rgb, mask, fora = classificar(img)
    conferir(mask)
    W, H = len(img[0]), len(img)
    tr = contorno(mask, fora)
    pa = particulas(mask)
    ha = halo(mask)
    q_monta = max(p[4] for p in pa) + A_DUR
    n_escudo = sum(l.count("s") for l in mask)
    n_raio = sum(l.count("r") for l in mask)

    if "--medir" in sys.argv:
        print(f"{W}×{H}  escudo {n_escudo}  raio {n_raio}  contorno {len(tr)}  "
              f"halo {len(ha)}  partículas {len(pa)}  LG_Q_MONTA {q_monta}  "
              f"produto (orçamento do ato 1) {q_monta * len(pa)}")
        return
    if "--preview" in sys.argv:
        for y in range(0, H, 2):
            linha = ""
            for x in range(W):
                i1, i2 = y * W + x, (y + 1) * W + x
                c1, c2 = mask[y][x], mask[y + 1][x]
                if c1 == "." and c2 == ".":
                    linha += " "; continue
                fg = "\033[38;2;%d;%d;%dm" % rgb[i1 if c1 != "." else i2]
                if c1 == ".":
                    linha += "\033[0m" + fg + "▄"
                elif c2 == ".":
                    linha += "\033[0m" + fg + "▀"
                else:
                    linha += fg + "\033[48;2;%d;%d;%dm" % rgb[i2] + "▀"
            print(linha + "\033[0m")
        print("\n" + "\n".join(mask))
        return

    print("# ── GERADO por tools/gera-logo.py — NÃO editar à mão ──────────────────────")
    print(f"# Escudo do ícone real (tools/app-icon-render.swift) em {W}×{H} pixels,")
    print(f"# com {margem} px de margem vazia para o halo e o traço não serem cortados.")
    print("# LG_MASK: . fora · s escudo · r raio. LG_RGB por pixel (y*LG_W+x).")
    print(f"LG_W={W}")
    print(f"LG_H={H}")
    print(f"LG_CAMINHO={len(tr)}")
    print(f"LG_Q_MONTA={q_monta}")
    print("LG_MASK=(")
    for l in mask:
        print(f"'{l}'")
    print(")")
    print(vetor("LG_RGB", ['"%d;%d;%d"' % c for c in rgb]))
    print(vetor("LG_TX", [p[0] for p in tr])); print(vetor("LG_TY", [p[1] for p in tr]))
    print(vetor("LG_AX", [p[0] for p in pa])); print(vetor("LG_AY", [p[1] for p in pa]))
    print(vetor("LG_AOX", [p[2] for p in pa])); print(vetor("LG_AOY", [p[3] for p in pa]))
    print(vetor("LG_ADL", [p[4] for p in pa]))
    print(vetor("LG_HX", [p[0] for p in ha])); print(vetor("LG_HY", [p[1] for p in ha]))


if __name__ == "__main__":
    main()
