#!/usr/bin/env python3
"""
gera-logo.py — gera o logo do River Bridge para a abertura do instalador.

A fonte é o ÍCONE REAL do app: roda tools/app-icon-render.swift (o mesmo render
que produz o AppIcon.icns), recorta o squircle, reduz a LADO×LADO pixels com o
`sips` do macOS e lê o BMP com a biblioteca padrão (sem PIL). Meio-bloco: cada
célula do terminal vira DOIS pixels (topo = frente do "▀", base = fundo), cada
pixel com a SUA cor de verdade — não uma paleta de classes.

Classes por pixel (LG_MASK):
    .  fora (transparente)      b  fundo do squircle (gradiente)
    s  escudo (branco)          r  raio (o vazado do escudo, brilha no batimento)

Saem também, em vetores paralelos (índice = y*LG_W + x quando é por pixel):
    LG_RGB              "r;g;b" de cada pixel (fora = "0;0;0")
    LG_TX/LG_TY         contorno do escudo, ordenado por posição de ARCO
                        (índice = posição: o traço desenha e retrai por arco)
    LG_AX/LG_AY/LG_AOX/LG_AOY/LG_ADL  partículas da constelação (só o escudo):
                        destino, origem fora do canvas (radial com giro de 40°)
                        e atraso — construção de baixo para cima, determinística
    LG_HX/LG_HY         o halo: pixels de fora encostados no squircle (o anel
                        que acende a cada batida do coração)

    ./tools/gera-logo.py            imprime o fragmento bash
    ./tools/gera-logo.py --preview  desenha no terminal (truecolor) para conferir
    ./tools/gera-logo.py --medir    só os números
    LADO=40 por padrão (20 linhas: o maior que cabe com o título em 24 linhas).
"""
import math, os, struct, subprocess, sys, tempfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LADO = int(os.environ.get("LADO", "40"))
INSET_PT, SQUIRCLE_PT, MASTER_PT = 60, 904, 1024   # geometria do app-icon-render.swift
A_DUR = 8                                           # quadros de voo de cada partícula


def renderizar_bmp(lado):
    """Ícone real → recorte do squircle → lado×lado → BMP 32 bpp. Devolve bytes."""
    work = tempfile.mkdtemp(prefix="gera-logo.")
    master = os.path.join(work, "master.png")
    subprocess.run(["swift", os.path.join(RAIZ, "tools", "app-icon-render.swift"), master],
                   check=True, stdout=subprocess.DEVNULL)
    out = subprocess.run(["sips", "-g", "pixelWidth", master], check=True,
                         capture_output=True, text=True).stdout
    px = int(out.strip().rsplit(":", 1)[1])
    escala = px / MASTER_PT                         # o AppKit renderiza em retina (2048)
    inset, lado_sq = round(INSET_PT * escala), round(SQUIRCLE_PT * escala)
    subprocess.run(["sips", "--cropOffset", str(inset), str(inset), "-c", str(lado_sq), str(lado_sq),
                    master], check=True, stdout=subprocess.DEVNULL)
    bmp = os.path.join(work, "small.bmp")
    subprocess.run(["sips", "-z", str(lado), str(lado), "-s", "format", "bmp", master, "--out", bmp],
                   check=True, stdout=subprocess.DEVNULL)
    return open(bmp, "rb").read()


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


def classificar(img):
    W, H = len(img[0]), len(img)
    rgb, mask = [], []
    for y in range(H):
        linha = []
        for x in range(W):
            r, g, b, a = img[y][x]
            if a < 96:
                linha.append("."); rgb.append((0, 0, 0)); continue
            # borda do squircle semi-transparente: compõe sobre preto (terminal escuro)
            r, g, b = r * a // 255, g * a // 255, b * a // 255
            rgb.append((r, g, b))
            linha.append("s" if min(r, g, b) >= 150 else "b")
        mask.append(linha)

    # O raio é o vazado do escudo: fundo NÃO alcançável a partir das bordas sem
    # atravessar o escudo. Flood fill de fora para dentro sobre não-'s'.
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
            if mask[y][x] == "b" and not fora[y][x]:
                mask[y][x] = "r"
    return rgb, ["".join(l) for l in mask], fora


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
    """Cada pixel do ESCUDO (s e r) ganha origem radial (giro de 40°) e atraso de
    baixo para cima — o mesmo desenho do gerador do haos-install; determinístico.
    Só o escudo voa: o fundo do squircle sobe como líquido (barato no bash — o
    custo por partícula é o que limita a fluidez, medido em 2026-09-01)."""
    W, H = len(mask[0]), len(mask)
    cx0, cy0 = W / 2.0, H / 2.0
    ys = [y for y in range(H) for x in range(W) if mask[y][x] in "sr"]
    y_base = max(ys)
    saida, i = [], 0
    for y in range(H):
        for x in range(W):
            if mask[y][x] not in "sr":
                continue
            ang = math.atan2(y + 0.5 - cy0, x + 0.5 - cx0) + math.radians(40)
            raio = W * 0.9 + (i % 9)
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
    img = ler_bmp(renderizar_bmp(LADO))
    rgb, mask, fora = classificar(img)
    W, H = LADO, LADO
    tr = contorno(mask, fora)
    pa = particulas(mask)
    ha = halo(mask)
    n_icone = sum(1 for l in mask for c in l if c != ".")
    n_escudo = sum(l.count("s") for l in mask)
    n_raio = sum(l.count("r") for l in mask)

    if "--medir" in sys.argv:
        print(f"lado {W}  ícone {n_icone} px  escudo {n_escudo}  raio {n_raio}  "
              f"contorno {len(tr)}  partículas {len(pa)}  halo {len(ha)}  "
              f"quadros da constelação {max(p[4] for p in pa) + A_DUR}")
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
    print(f"# Ícone real do app (tools/app-icon-render.swift) reduzido a {W}×{H} pixels.")
    print("# LG_MASK: . fora · b fundo · s escudo · r raio. LG_RGB por pixel (y*LG_W+x).")
    print(f"LG_W={W}")
    print(f"LG_H={H}")
    print(f"LG_CAMINHO={len(tr)}")
    print(f"LG_Q_MONTA={max(p[4] for p in pa) + A_DUR}")
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
