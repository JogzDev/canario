"""Motor, passo 1: liga produto a termo da taxonomia (§11, §17).

Sem isto a perna de varejo nao alimenta indice nenhum: 65 mil produtos
coletados e nenhum sabendo o que e. O coletor guarda o cru de proposito (B2: o
casamento e retroativo, e a taxonomia so foi aprovada em 28/07); e aqui que o
cru vira atributo.

O que faz:
  * casa titulo + descricao contra `palavras_pt` e `palavras_en` dos termos
    APROVADOS (regra 4), com o `matcher` de correspondencia exata -- o mesmo que
    ja carrega a regressao `reta` nao casa `preta`;
  * grava em `produto_termos` com origem='titulo';
  * preenche `produtos.segmento` (B4).

Sobre o segmento: o coletor so desce departamentos que o classificador aprova
como vestuario feminino, em TODO nivel da arvore. A marca fornece o segmento
operacional de fallback; o produto continua sendo a coluna autoritativa (B4).
Isto importa quando dois paineis coexistem: uma Dôen nunca pode ser rebatizada
silenciosamente como feminino_casual_br pelo motor da madrugada.

Idempotente: pode rodar todo dia. O casamento inteiro vai para um stage
invisivel; so depois de todos os produtos chegarem um job interno troca o
estado vivo em uma transacao. Uma queda no meio preserva a taxonomia anterior.
"""

import os
import re
import sys
import time
import urllib.parse
import uuid
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import (compilar_lista, termos_que_casam, casa_algum,  # noqa: E402
                     normalizar)
import supabase_rest  # noqa: E402

# Filtro de POPULACAO no nivel do PRODUTO.
#
# O filtro por departamento nao basta: a Hering organiza o catalogo por PECA
# (Blusas, Calcas, Camisetas, Polos), sem departamento de genero. O
# `loja_so_feminina()` nao acha nada masculino no topo, conclui "loja so
# feminina" e entra em tudo -- e 4.386 dos 7.778 produtos dela (56%) sao de
# outro publico. Numa marca `ancora`, isso contamina o share de atributo do
# painel inteiro.
#
# O titulo do produto diz o que a arvore de categorias escondeu.
FORA_DO_SEGMENTO = compilar_lista([
    # outro publico
    "masculin*", "menino*", "menina*", "infant*", "kids", "bebe*", "baby",
    "homem", "homens", "teen", "junior", "men", "mens", "boys", "girls",
    # outro segmento (§8: o recorte e casual/social, nao intimo nem praia)
    "calcinha*", "sutia*", "lingerie", "cueca*", "pijama*", "camisola*",
    "biquini*", "maio", "maios", "sunga*", "moda praia", "beachwear",
    "bikini*", "swimwear", "sleepwear", "underwear",
])


def fora_do_segmento(texto):
    """True quando o proprio produto se declara de outra populacao."""
    return casa_algum(texto, FORA_DO_SEGMENTO)


# Acessorio e calcado, reconhecidos pelo INICIO do titulo.
#
# Por que no inicio, e nao em qualquer posicao: medido no painel em 01/08/2026,
# a palavra `cinto` aparece em 1.117 titulos, e so 127 deles sao cintos -- os
# outros 990 sao vestidos e macacoes "com cinto". `lenco` aparece em 207, e 158
# sao "Calca Lenco" e "Saia Lenco". Uma regra que valesse em qualquer posicao
# jogaria fora quase mil pecas de roupa.
#
# No outro sentido a ancora quase nao custa: `bolsa` casa 509 titulos e 499
# comecam com ela; `brinco`, 341 contra 336. Titulo de e-commerce brasileiro
# comeca pelo tipo do produto, e e nisso que a regra se apoia.
#
# Isto entrou porque 1.425 acessorios (2,3% do painel) estavam sendo tratados
# como roupa, e 281 ja tinham recebido categoria de vestuario -- um colar
# apareceria como "peca parecida" com um vestido no bloco de similares (§29).
# O filtro por arvore de categoria nao pega: a Shopify nao expoe arvore, entao
# a PatBo entrava inteira, com 256 bolsas, 70 sandalias e 66 brincos.
ACESSORIO = [
    # calcado
    "sandalia", "sapato", "sapatilha", "tenis", "tamanco", "mule", "scarpin",
    "rasteira", "rasteirinha", "bota", "botas", "botina", "coturno", "chinelo",
    "papete", "mocassim", "slide", "sapatenis",
    # bolsa e afins
    "bolsa", "bolsas", "bolsinha", "clutch", "mochila", "carteira", "necessaire",
    "pochete", "shopper",
    # joia e bijuteria
    "brinco", "brincos", "colar", "colares", "anel", "aneis", "pulseira",
    "pulseiras", "bracelete", "tornozeleira", "choker", "piercing", "corrente",
    "argola", "argolas",
    # outros acessorios
    "cinto", "cintos", "oculos", "chapeu", "bone", "lenco", "echarpe", "luva",
    "luvas", "meia", "meias", "gravata", "viseira", "bandana", "tiara",
    "presilha", "guarda-chuva",
    # beleza, que aparece em marca de grupo
    "perfume", "hidratante", "batom", "esmalte", "sabonete",
    # equivalentes das lojas internacionais do painel de direção
    "shoe", "shoes", "sneaker", "sneakers", "sandal", "sandals", "boot",
    "boots", "bag", "bags", "handbag", "handbags", "purse", "purses",
    "earring", "earrings", "necklace", "necklaces", "bracelet", "bracelets",
    "ring", "rings", "belt", "belts", "hat", "hats", "sunglasses",
]

# A mesma lista para o campo de categoria do site, onde a palavra pode estar em
# qualquer posicao: ali o texto e estruturado ("/Feminino/Brincos/", "BOLSA"),
# nao e frase, e o risco de falso positivo nao existe.
_ACESSORIO_NO_INICIO = re.compile(
    r"^(?:" + "|".join(re.escape(p) for p in ACESSORIO) + r")s?\b",
    re.IGNORECASE)
_ACESSORIO_NA_CATEGORIA = compilar_lista(
    [p + "*" for p in ACESSORIO] + ["acessorio*", "joia", "joias", "bijuteria*",
                                    "calcado*", "sapatos", "accessor*", "jewelry",
                                    "footwear"],
    flexionar=False)


def e_acessorio(titulo, categoria_site):
    """True quando o produto nao e peca de roupa.

    Duas portas, e basta uma: o titulo COMECA com o tipo do acessorio, ou a
    categoria do site o nomeia. A segunda existe para o item mal titulado; a
    primeira, para a loja que nao expoe categoria.
    """
    if titulo and _ACESSORIO_NO_INICIO.match(normalizar(titulo).lstrip()):
        return True
    if categoria_site and casa_algum(normalizar(categoria_site),
                                     _ACESSORIO_NA_CATEGORIA):
        return True
    return False

PAGINA = 1000
BLOCO_ESCRITA = 500


def limpar_nome_da_marca(texto, nome_marca):
    """Tira o nome da marca do texto antes de casar atributo.

    MEDIDO EM 01/08/2026, e o estrago era grande:

      * O caminho de categoria da Dress To e `/dress to/Bazar/Blusas/`, e
        `dress` esta em `vestido.palavras_en`. Resultado: **os 6.895 produtos
        da marca inteira** viraram `vestido` -- calca, blusa, saia e bolsa
        junto. Eram 41,3% de todas as ligacoes de `vestido` no painel.
      * "Morena Rosa" no titulo dava `vermelho_rosa` a 612 produtos, 11,2% das
        ligacoes daquele termo.

    E o mesmo erro de origem que ja apareceu duas vezes neste projeto: texto que
    nao descreve a peca entrando como se descrevesse. Antes foi a descricao de
    marketing (30/07), depois o `content:encoded` do editorial. Agora e o nome
    de quem vende.

    A limpeza vale para toda marca, e nao so para as duas que colidem hoje: uma
    marca nova chamada "Linho" ou "Preta" reintroduziria o problema em silencio.
    """
    if not texto or not nome_marca:
        return texto or ""
    alvo = normalizar(nome_marca)
    if not alvo:
        return texto
    # Palavra inteira, para "NV" nao comer o "nv" de outra palavra e para
    # "Farm" nao comer "farmacia".
    padrao = r"\b" + re.escape(alvo).replace(r"\ ", r"\s+") + r"\b"
    return re.sub(padrao, " ", normalizar(texto))


def carregar_termos():
    """Termos aprovados -> {id: [regex]}, e o conjunto de ids de categoria."""
    aprovados = supabase_rest.selecionar(
        "termos",
        "?status=eq.aprovado&select=id,rotulo,dimensao,palavras_pt,palavras_en")
    categorias = {t["id"] for t in aprovados if t.get("dimensao") == "categoria"}
    compilados = {}
    for t in aprovados:
        padroes = []
        for campo in ("palavras_pt", "palavras_en"):
            valor = (t.get(campo) or "").strip()
            if valor:
                padroes.extend(p for p in valor.split("|") if p.strip())
        if t.get("rotulo"):
            padroes.append(t["rotulo"])
        regexes = compilar_lista(padroes)
        if regexes:
            compilados[t["id"]] = regexes
    return compilados, categorias


def produtos_em_paginas():
    """Percorre os produtos em paginas, pelo id, sem segurar tudo em memoria."""
    ultimo = 0
    while True:
        lote = supabase_rest.selecionar(
            "produtos",
            # `descricao` saiu do select em 20/08/2026: ela era baixada em toda
            # execucao e DESCARTADA logo em seguida -- o casamento usa titulo +
            # categoria de proposito desde 30/07, quando medimos que 74% dos
            # casamentos de `reta_wide` vinham da prosa de marketing. Eram 53 MB
            # atravessando a rede a cada motor para nao serem lidos.
            "?id=gt.{}&select=id,titulo,categoria_site,segmento,marca_id"
            "&order=id.asc&limit={}".format(ultimo, PAGINA))
        if not lote:
            return
        yield lote
        ultimo = lote[-1]["id"]


def publicar_e_aguardar(execucao, total, intervalo=10, limite=1800):
    """Agenda a transacao no Postgres e acompanha sem segurar uma RPC longa."""
    _, fila = supabase_rest._requisicao(
        "POST", "rpc/solicitar_publicacao_motor",
        corpo={"p_execucao": execucao, "p_total": total}, tentativas=1)
    print("Publicacao atomica agendada: {}.".format(fila), file=sys.stderr)

    inicio = time.monotonic()
    ultimo_status = None
    filtro = ("?execucao=eq.{}&select=status,resultado,erro,solicitado_em,"
              "iniciado_em,concluido_em&limit=1").format(
                  urllib.parse.quote(execucao))
    while True:
        linhas = supabase_rest.selecionar("motor_execucoes", filtro)
        if not linhas:
            raise supabase_rest.SupabaseErro(
                "publicacao {} desapareceu da fila".format(execucao))
        estado = linhas[0]
        status = estado.get("status")
        if status != ultimo_status:
            print("Publicacao do motor: {}.".format(status), file=sys.stderr)
            ultimo_status = status
        if status == "success":
            return estado.get("resultado")
        if status == "failed":
            raise supabase_rest.SupabaseErro(
                "publicacao atomica falhou: {}".format(
                    estado.get("erro") or "erro nao informado"))
        if time.monotonic() - inicio >= limite:
            raise supabase_rest.SupabaseErro(
                "publicacao {} nao concluiu em {}s".format(execucao, limite))
        time.sleep(intervalo)


def preparar_stage():
    """Descarta preparacao orfa antes de escrever um novo lote.

    A RPC recusa agir se houver uma publicacao queued/running. Isso torna o
    `TRUNCATE` seguro e recupera tambem uma queda do runner que aconteca antes
    de a execucao chegar a `motor_execucoes`.
    """
    _, resultado = supabase_rest._requisicao(
        "POST", "rpc/preparar_stage_motor", corpo={}, tentativas=1)
    print("Stage do motor: {}.".format(resultado), file=sys.stderr)


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    termos, categorias = carregar_termos()
    if not termos:
        print("Nenhum termo aprovado com palavras.", file=sys.stderr)
        return 0
    print("Termos aprovados: {} ({} categorias)".format(
        len(termos), len(categorias)), file=sys.stderr)

    preparar_stage()

    execucao = str(uuid.uuid4())
    print("Preparando atributos na execucao {}.".format(execucao),
          file=sys.stderr)

    total = casados = ligacoes = fora = 0
    sem_categoria = 0
    # id -> configuracao. O segmento da marca e apenas o fallback que o B4
    # previu; cada produto recebe sua propria copia no stage atomico.
    marcas = {m["id"]: m
              for m in supabase_rest.selecionar(
                  "marcas", "?select=id,nome,segmento")}

    buffer_pt, buffer_produtos = [], []

    for lote in produtos_em_paginas():
        for p in lote:
            total += 1
            # TITULO + CATEGORIA, nunca a descricao.
            #
            # §28 diz que "titulos de e-commerce sao etiquetas quase prontas", e
            # e literal: o titulo e escrito para identificar a peca. A descricao
            # e texto de marketing, cheio de adjetivo solto -- medido em 30/07,
            # 74% dos casamentos de `reta_wide` vinham dela, e o exemplo tipico
            # era uma camiseta com "caimento amplo e despojado" virando silhueta
            # de perna. Mesmo erro que o `content:encoded` causou no editorial.
            #
            # Tecido continua recuperavel depois por `snapshots.composicao`, que
            # e campo estruturado, e nao prosa publicitaria.
            texto = " ".join(filter(None, [p.get("titulo"),
                                           p.get("categoria_site")]))
            # O nome de quem vende nao descreve o que se vende.
            marca = marcas.get(p.get("marca_id")) or {}
            texto = limpar_nome_da_marca(texto, marca.get("nome"))
            # Antes de casar atributo: este produto pertence ao segmento?
            #
            # Duas perguntas diferentes. `fora_do_segmento` pergunta se e OUTRA
            # POPULACAO (masculino, infantil, praia, intimo). `e_acessorio`
            # pergunta se e OUTRO TIPO DE PRODUTO -- bolsa, sandalia, brinco --
            # que e roupa de ninguem. As duas tiram o produto do segmento.
            if fora_do_segmento(texto) or e_acessorio(p.get("titulo"),
                                                      p.get("categoria_site")):
                fora += 1
                buffer_produtos.append({
                    "execucao": execucao,
                    "produto_id": p["id"],
                    "segmento": None,
                })
                continue
            achados = termos_que_casam(texto, termos) if texto.strip() else set()
            if achados:
                casados += 1
                if not (achados & categorias):
                    # Vale registrar: produto com atributo e sem categoria fica
                    # invisivel na leitura do §11 ("categoria e filtro").
                    sem_categoria += 1
                for termo_id in achados:
                    buffer_pt.append({
                        "execucao": execucao,
                        "produto_id": p["id"],
                        "termo_id": termo_id,
                    })
                    ligacoes += 1
            buffer_produtos.append({
                "execucao": execucao,
                "produto_id": p["id"],
                "segmento": marca.get("segmento"),
            })

            if len(buffer_pt) >= BLOCO_ESCRITA:
                supabase_rest.upsert(
                    "motor_termos_stage", buffer_pt,
                    on_conflict="execucao,produto_id,termo_id")
                buffer_pt = []
        # Todos os produtos recebem uma linha, inclusive os fora do segmento.
        # A RPC usa essa cardinalidade para rejeitar stage parcial antes de
        # tocar nas tabelas vivas.
        supabase_rest.upsert(
            "motor_produtos_stage", buffer_produtos,
            on_conflict="execucao,produto_id")
        buffer_produtos = []
        print("  {} produtos processados, {} com atributo, {} ligacoes".format(
            total, casados, ligacoes), file=sys.stderr)

    if buffer_pt:
        supabase_rest.upsert(
            "motor_termos_stage", buffer_pt,
            on_conflict="execucao,produto_id,termo_id")

    publicado = publicar_e_aguardar(execucao, total)
    print("Atributos e calculos publicados atomicamente: {}.".format(publicado),
          file=sys.stderr)

    pct = (100.0 * casados / total) if total else 0
    print("\n{} produtos, {} com pelo menos um termo ({:.1f}%), {} ligacoes.".format(
        total, casados, pct, ligacoes), file=sys.stderr)
    print("Com atributo mas sem categoria: {} (ficam fora da leitura do §11)".format(
        sem_categoria), file=sys.stderr)
    print("FORA do segmento por populacao (masculino, infantil, intimo, praia): {}".format(
        fora), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
