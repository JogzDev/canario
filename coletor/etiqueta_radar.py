"""Parser local e conservador de etiquetas de composicao em PT-BR.

O modulo separa tres coisas que os campos ``Composicao`` e ``Material`` dos
catalogos costumam misturar:

* componentes da composicao, com o percentual quando ele foi declarado;
* construcao do tecido (malha, sarja, denim, trico...);
* acabamento aparente (estonado, bordado, metalizado...).

As regras sao deliberadamente fechadas. Uma palavra desconhecida nao e
completada por semelhanca e uma aparencia de fibra ("toque de seda") nao vira
composicao. Isso permite usar o resultado no Etiqueta Radar sem rede, modelo ou
dependencia externa e, principalmente, permite ao parser se abster.
"""

from __future__ import annotations

import re
import unicodedata


VERSAO_PARSER = "etiqueta-radar-rule-v1"
VERSAO_DO_PARSER = VERSAO_PARSER
LIMITE_CARACTERES = 20_000


# ``fibra_id`` e o nome historico do contrato. A lista inclui alguns materiais
# nao fibrosos que aparecem legitimamente numa composicao percentual (couro,
# poliuretano e PVC). O parser preserva o que a etiqueta declarou; nao tenta
# transformar esses materiais em fibras texteis.
_FIBRAS = {
    "algodao": (
        "algodao organico", "algodao reciclado", "fibra de algodao",
        "algodao", "cotton",
    ),
    "poliester": (
        "poliester reciclado", "fibra de poliester", "poliester", "polyester",
    ),
    "poliamida": ("poliamida reciclada", "poliamida", "nylon", "polyamide"),
    "elastano": ("elastano", "elastane", "spandex", "lycra"),
    "viscose": ("viscose certificada", "viscose", "rayon"),
    "linho": ("fibra de linho", "linho", "linen"),
    "la": ("la merino", "la virgem", "fibra de la", "la", "wool"),
    "acrilico": ("fibra acrilica", "acrilico", "acrylic"),
    "modal": ("micromodal", "micro modal", "modal"),
    "liocel": ("tencel lyocell", "lyocell", "liocel", "tencel"),
    "seda": ("seda natural", "fibra de seda", "seda", "silk"),
    "acetato": ("acetato", "acetate"),
    "triacetato": ("triacetato", "triacetate"),
    "cupro": ("cupro",),
    "caxemira": ("cashmere", "caxemira", "casimira"),
    "alpaca": ("alpaca",),
    "canhamo": ("fibra de canhamo", "canhamo", "hemp"),
    "juta": ("juta",),
    "rami": ("ramie", "rami"),
    "bambu": ("fibra de bambu", "bamboo fiber", "bambu"),
    "polipropileno": ("polipropileno", "polypropylene"),
    "polietileno": ("polietileno", "polyethylene"),
    "poliuretano": ("poliuretano", "polyurethane", "pu"),
    "elastomultiester": ("elastomultiester", "elastomultiester"),
    "aramida": ("aramida", "aramid"),
    "fibra_metalica": ("fibra metalizada", "fibra metalica", "metallic fiber"),
    "couro_sintetico": (
        "couro sintetico", "couro vegano", "couro pu", "synthetic leather",
        "vegan leather", "courino", "corino",
    ),
    "couro": ("couro genuino", "couro natural", "couro", "leather"),
    "latex": ("latex natural", "latex"),
    "borracha": ("borracha natural", "borracha", "rubber"),
    "pvc": ("policloreto de vinila", "cloreto de polivinila", "pvc"),
}


_CONSTRUCOES = {
    # Especificos antes dos genericos: a selecao por maior trecho tambem
    # impede que "malha canelada" devolva uma segunda evidencia "malha".
    "malha_canelada": ("malha canelada", "rib knit"),
    "malha_fria": ("malha fria",),
    "tecido_plano": ("tecido plano", "flat woven", "woven fabric"),
    "jersey": ("malha jersey", "jersey"),
    "interlock": ("malha interlock", "interlock"),
    "ribana": ("malha ribana", "ribana"),
    "malha": ("malhas", "malha", "knit fabric"),
    "trico": ("tricot", "trico", "knitted"),
    "croche": ("croche", "crochet"),
    "denim": ("denim", "jeans"),
    "sarja": ("sarja", "twill"),
    "brim": ("brim",),
    "tricoline": ("tricoline", "popeline", "poplin"),
    "crepe": ("crepe",),
    "cetim": ("cetim", "satin"),
    "jacquard": ("jacquard",),
    "renda": ("renda guipir", "renda chantilly", "guipure", "renda", "lace"),
    "tule": ("tule", "tulle"),
    "chiffon": ("chiffon", "chifon"),
    "organza": ("organza",),
    "georgette": ("georgette",),
    "voal": ("voile", "voal"),
    "tafeta": ("tafeta", "taffeta"),
    "veludo": ("veludo cotelê", "veludo cotele", "veludo", "velvet"),
    "boucle": ("boucle", "boucle"),
    "piquet": ("piquet", "pique"),
    "moletom": ("moletom", "sweatshirt fleece"),
    "fleece": ("polar fleece", "fleece"),
    "sherpa": ("sherpa",),
    "neoprene": ("neoprene",),
    "gabardine": ("gabardine",),
    "oxford": ("oxford",),
    "cambraia": ("cambraia",),
    "laise": ("tecido laise", "laise"),
    "matelasse": ("matelasse", "matelassê"),
    "mesh": ("malha mesh", "power mesh", "mesh"),
    "tela": ("tecido telado", "tela textil"),
    "tactel": ("tactel",),
    "suplex": ("suplex",),
    "microfibra": ("microfibra",),
    "pelucia": ("pelucia", "plush"),
    "suede": ("suede", "camurca sintetica"),
}


_ACABAMENTOS = {
    "estonado": ("lavagem estonada", "stone washed", "stonewash", "estonado", "estonada"),
    "delave": ("lavagem delave", "delave"),
    "acid_wash": ("acid wash", "acid washed"),
    "destroyed": ("efeito destroyed", "destroyed", "puido", "puida"),
    "desfiado": ("barra desfiada", "acabamento desfiado", "desfiado", "desfiada"),
    "resinado": ("acabamento resinado", "resinado", "resinada"),
    "encerado": ("efeito encerado", "encerado", "encerada", "waxed"),
    "revestido": ("acabamento coated", "tecido revestido", "coated fabric"),
    "metalizado": ("efeito metalizado", "metalizado", "metalizada", "metallic finish"),
    "foil": ("aplicacao de foil", "foil"),
    "lurex": ("fio de lurex", "fios de lurex", "lurex"),
    "lame": ("lame", "lamé"),
    "glitter": ("aplicacao de glitter", "glitter"),
    "paete": ("aplicacao de paetes", "aplicacao de paete", "paetes", "paete", "sequin"),
    "bordado": ("bordado ingles", "bordado", "bordada", "embroidered"),
    "pedraria": ("aplicacao de pedrarias", "pedrarias", "pedraria", "strass", "cristais"),
    "franjas": ("acabamento de franjas", "franjas"),
    "plissado": ("efeito plissado", "plissado", "plissada", "pleated"),
    "amassado": ("efeito amassado", "efeito crinkle", "crinkle"),
    "devore": ("devore",),
    "flocado": ("acabamento flocado", "flocado", "flocada", "flocked"),
    "aveludado": ("toque aveludado", "acabamento aveludado", "aveludado", "aveludada"),
    "escovado": ("acabamento escovado", "escovado", "escovada", "brushed"),
    "peletizado": ("acabamento peletizado", "peletizado", "peletizada", "peach skin"),
    "mercerizado": ("algodao mercerizado", "mercerizado", "mercerizada"),
    "tie_dye": ("tie dye", "tie-dye"),
    "degrade": ("efeito degrade", "degrade"),
    "estampado": ("estampa localizada", "estampado", "estampada", "printed"),
    "texturizado": ("efeito texturizado", "texturizado", "texturizada"),
    "cirre": ("efeito cirre", "cirre"),
}


_PARTES = {
    "parte externa": "exterior",
    "camada externa": "exterior",
    "exterior": "exterior",
    "externo": "exterior",
    "externa": "exterior",
    "corpo": "corpo",
    "body": "corpo",
    "forro": "forro",
    "lining": "forro",
    "enchimento": "enchimento",
    "padding": "enchimento",
    "revestimento": "revestimento",
    "coating": "revestimento",
    "detalhe": "detalhe",
    "detalhes": "detalhe",
    "recorte": "recorte",
    "recortes": "recorte",
    "renda": "renda",
    "bordado": "bordado",
    "punho": "punho",
    "punhos": "punho",
    "gola": "gola",
    "bolso": "bolso",
    "bolsos": "bolso",
    "elastico": "elastico",
    "principal": "principal",
    "tecido": "principal",
}


_SEM_DADO = re.compile(
    r"\b(?:composicao|material|tecido)?\s*(?:nao\s+informad[oa]s?|"
    r"nao\s+disponivel|indisponivel|nao\s+especificad[oa]s?|a\s+definir)\b|"
    r"\b(?:consulte|consultar|ver|vide)\s+(?:a\s+)?etiqueta\b|"
    r"\bsem\s+informac(?:ao|oes)\b"
)

_PERCENTUAL = r"(?:100(?:[\.,]0{1,2})?|\d{1,2}(?:[\.,]\d{1,2})?)"


def _sem_acentos(texto: str, preservar_tamanho: bool = False) -> str:
    """Devolve minusculas sem acento; opcionalmente mantem indices da fonte."""
    if not preservar_tamanho:
        decomposto = unicodedata.normalize("NFKD", texto)
        texto = "".join(c for c in decomposto if not unicodedata.combining(c))
        return re.sub(r"\s+", " ", texto.lower()).strip()

    saida = []
    for caractere in texto:
        if caractere.isspace():
            saida.append(" ")
            continue
        bases = [c for c in unicodedata.normalize("NFKD", caractere)
                 if not unicodedata.combining(c)]
        # Os caracteres usados nas etiquetas decompoem para exatamente uma
        # base. O fallback conserva um indice por caractere mesmo em lixo raro.
        saida.append(("".join(bases) or caractere).lower()[0])
    return "".join(saida)


def _alternativas(valores) -> str:
    unicos = sorted({_sem_acentos(v) for v in valores}, key=len, reverse=True)
    return "(?:" + "|".join(
        re.escape(v).replace(r"\ ", r"\s+") for v in unicos
    ) + ")"


_ALIAS_PARA_FIBRA = {}
for _fibra_id, _aliases in _FIBRAS.items():
    for _alias in _aliases:
        _ALIAS_PARA_FIBRA[_sem_acentos(_alias)] = _fibra_id

_TODOS_ALIASES_FIBRA = tuple(_ALIAS_PARA_FIBRA)
_RE_ALIAS_FIBRA = _alternativas(_TODOS_ALIASES_FIBRA)
_RE_FIBRA_DEPOIS = re.compile(
    r"(?<![\d\.,])(?P<pct>" + _PERCENTUAL + r")(?![\d\.,])"
    r"\s*%\s*(?:de\s+)?"
    r"(?P<fibra>" + _RE_ALIAS_FIBRA + r")(?!\w)"
)
_RE_FIBRA_ANTES = re.compile(
    r"(?<!\w)(?P<fibra>" + _RE_ALIAS_FIBRA + r")(?!\w)"
    r"\s*(?:[:=\-]\s*)?(?P<pct>" + _PERCENTUAL + r")(?![\d\.,])\s*%"
)
_RE_FIBRA_SO = re.compile(
    r"(?<!\w)(?P<fibra>" + _RE_ALIAS_FIBRA + r")(?!\w)"
)
_RE_QUALIFICADOR_DEPOIS = re.compile(
    r"\s+(?:organico|organica|reciclado|reciclada|certificado|certificada)\b"
)
_RE_QUALIFICADOR_ANTES_PCT = re.compile(
    r"\s+(?:organico|organica|reciclado|reciclada|certificado|certificada)"
    r"(?=\s*(?:[:=\-]\s*)?" + _PERCENTUAL + r"\s*%)"
)
_RE_PERCENTUAL_SOLTO = re.compile(
    r"(?<!\d)\d{1,6}(?:[\.,]\d+)?\s*%"
)

_RE_PARTES = re.compile(
    r"(?<!\w)(?P<parte>" + _alternativas(_PARTES) + r")(?!\w)\s*:?(?:\s+em)?"
)

_NEGACAO_ANTES = re.compile(
    r"(?:\bsem|\bnao|\bnem|\bexceto|\blivre\s+de|\bausencia\s+de)"
    r"(?:\s+\w+){0,3}\s*$"
)
_APARENCIA_DE_FIBRA = re.compile(
    r"(?:\btoque|\befeito|\baspecto|\bvisual|\baparencia|\bimitacao|"
    r"\bsimilar|\bsemelhante|\btipo)\s+(?:de\s+|a\s+|d[oa]\s+)?$"
)
_APARENCIA_DE_CONSTRUCAO = re.compile(
    r"(?:\befeito|\baspecto|\bvisual|\baparencia|\bimitacao|\bestampa)"
    r"\s+(?:de\s+|a\s+|d[oa]\s+)?$"
)


def _trecho(texto: str, inicio: int, fim: int) -> str:
    return re.sub(r"\s+", " ", texto[inicio:fim]).strip()


def _sobrepoe(inicio: int, fim: int, intervalos) -> bool:
    return any(inicio < outro_fim and fim > outro_inicio
               for outro_inicio, outro_fim in intervalos)


def _negado(texto_normalizado: str, inicio: int) -> bool:
    prefixo = texto_normalizado[max(0, inicio - 55):inicio]
    # Pontuacao forte inicia uma nova afirmacao.
    prefixo = re.split(r"[;\.!?\n]", prefixo)[-1]
    return bool(_NEGACAO_ANTES.search(prefixo))


def _contexto_aparente(texto_normalizado: str, inicio: int, tipo: str) -> bool:
    prefixo = texto_normalizado[max(0, inicio - 45):inicio]
    prefixo = re.split(r"[;,\.!?\n]", prefixo)[-1]
    regra = _APARENCIA_DE_FIBRA if tipo == "fibra" else _APARENCIA_DE_CONSTRUCAO
    return bool(regra.search(prefixo))


def _parte_no_ponto(texto_normalizado: str, inicio: int) -> str:
    ultima = None
    for casamento in _RE_PARTES.finditer(texto_normalizado, 0, inicio):
        ultima = casamento
    if ultima is None:
        return "principal"

    # Um cabecalho muito distante nao deve vazar para outro paragrafo. Dentro
    # de 160 caracteres ele cobre listas como "Corpo: 95% ..., 5% ...".
    entre = texto_normalizado[ultima.end():inicio]
    if len(entre) > 160 or re.search(r"[\.!?\n]", entre):
        return "principal"
    alias = _sem_acentos(ultima.group("parte"))
    return _PARTES.get(alias, "principal")


def _percentual(valor: str):
    numero = float(valor.replace(",", "."))
    return int(numero) if numero.is_integer() else numero


def _fibra_id(alias: str) -> str:
    return _ALIAS_PARA_FIBRA[_sem_acentos(alias)]


def _extrair_composicao(texto: str, normalizado: str):
    candidatos = []
    for regra in (_RE_FIBRA_DEPOIS, _RE_FIBRA_ANTES):
        for casamento in regra.finditer(normalizado):
            inicio, fim = casamento.span()
            # Inclui qualificadores contiguos no trecho-fonte, mas eles nunca
            # alteram a fibra canonica nem inventam certificacao.
            if regra is _RE_FIBRA_DEPOIS:
                qualificador = _RE_QUALIFICADOR_DEPOIS.match(normalizado, fim)
                if qualificador:
                    fim = qualificador.end()
            else:
                qualificador = _RE_QUALIFICADOR_ANTES_PCT.match(
                    normalizado, casamento.end("fibra"))
                if qualificador:
                    # A propria regex principal comeca o percentual depois do
                    # alias; qualificadores pre-percentual sao reconhecidos por
                    # aliases compostos. Este ramo apenas documenta a fronteira.
                    fim = casamento.end()
            if _negado(normalizado, inicio) or _contexto_aparente(
                    normalizado, casamento.start("fibra"), "fibra"):
                continue
            candidatos.append({
                "fibra_id": _fibra_id(casamento.group("fibra")),
                "percentual": _percentual(casamento.group("pct")),
                "trecho_fonte": _trecho(texto, inicio, fim),
                "parte_id": _parte_no_ponto(normalizado, inicio),
                "_span": (inicio, fim),
            })

    # Primeiro o maior casamento; isso elimina a duplicacao entre as duas
    # orientacoes e entre aliases compostos/simples.
    candidatos.sort(key=lambda item: (
        item["_span"][0], -(item["_span"][1] - item["_span"][0])
    ))
    escolhidos = []
    intervalos = []
    for item in candidatos:
        inicio, fim = item["_span"]
        if _sobrepoe(inicio, fim, intervalos):
            continue
        if not 0 < float(item["percentual"]) <= 100:
            continue
        escolhidos.append(item)
        intervalos.append((inicio, fim))

    # Fibra declarada sem percentual continua sendo evidencia, mas o ``None``
    # impede qualquer consumidor de tratar a lista como uma mistura que fecha.
    for casamento in _RE_FIBRA_SO.finditer(normalizado):
        inicio, fim = casamento.span()
        if _sobrepoe(inicio, fim, intervalos):
            continue
        if _negado(normalizado, inicio) or _contexto_aparente(
                normalizado, inicio, "fibra"):
            continue
        parte_id = _parte_no_ponto(normalizado, inicio)
        # Campos bilingues repetem com frequencia "100% algodao / cotton".
        # A segunda grafia sem numero nao e um segundo componente.
        if any(item["fibra_id"] == _fibra_id(casamento.group("fibra")) and
               item["parte_id"] == parte_id for item in escolhidos):
            continue
        escolhidos.append({
            "fibra_id": _fibra_id(casamento.group("fibra")),
            "percentual": None,
            "trecho_fonte": _trecho(texto, inicio, fim),
            "parte_id": parte_id,
            "_span": (inicio, fim),
        })
        intervalos.append((inicio, fim))

    escolhidos.sort(key=lambda item: item["_span"][0])
    return escolhidos, intervalos


def _compilar_lexico(lexico):
    regras = []
    for item_id, aliases in lexico.items():
        for alias in aliases:
            padrao = _sem_acentos(alias)
            regex = re.compile(
                r"(?<!\w)" + re.escape(padrao).replace(r"\ ", r"\s+") +
                r"(?!\w)"
            )
            regras.append((item_id, regex, len(padrao)))
    return regras


_REGRAS_CONSTRUCAO = _compilar_lexico(_CONSTRUCOES)
_REGRAS_ACABAMENTO = _compilar_lexico(_ACABAMENTOS)


def _extrair_lexico(texto: str, normalizado: str, regras, tipo: str):
    candidatos = []
    for item_id, regra, tamanho in regras:
        for casamento in regra.finditer(normalizado):
            inicio, fim = casamento.span()
            if _negado(normalizado, inicio):
                continue
            if tipo == "construcao" and _contexto_aparente(
                    normalizado, inicio, "construcao"):
                continue
            candidatos.append((inicio, fim, -tamanho, item_id))

    # Maior evidencia vence no mesmo ponto; conceitos repetidos e trechos
    # sobrepostos aparecem uma unica vez no contrato publico.
    candidatos.sort(key=lambda candidato: (
        candidato[0], -(candidato[1] - candidato[0]), candidato[3]
    ))
    intervalos = []
    ids = set()
    saida = []
    for inicio, fim, _, item_id in candidatos:
        if item_id in ids or _sobrepoe(inicio, fim, intervalos):
            continue
        ids.add(item_id)
        intervalos.append((inicio, fim))
        saida.append({
            "item_id": item_id,
            "trecho_fonte": _trecho(texto, inicio, fim),
        })
    return saida


def _resultado_vazio(motivo: str, texto_normalizado: str = ""):
    return {
        "versao": VERSAO_PARSER,
        "texto_normalizado": texto_normalizado,
        "composicao": [],
        "construcao": [],
        "acabamento": [],
        "abstencao": True,
        "motivos_abstencao": [motivo],
        "campos_abstidos": ["composicao", "construcao", "acabamento"],
        "confianca": "nenhuma",
        "explicacao_confianca": "nenhuma evidencia inequivoca foi reconhecida",
        "avisos": [],
    }


def analisar_etiqueta(texto):
    """Analisa uma string de ``Composicao``/``Material`` sem sair do processo.

    O retorno e composto apenas de tipos JSON. ``abstencao`` e global: fica
    verdadeiro quando nenhuma das tres dimensoes tem evidencia segura. Campos
    individualmente vazios sao listados em ``campos_abstidos``. Uma etiqueta
    parcialmente aproveitavel nao perde fatos explicitos; anomalias ficam em
    ``avisos`` e reduzem a faixa descritiva de ``confianca``.
    """
    if texto is None:
        return _resultado_vazio("entrada_nula")
    if not isinstance(texto, str):
        return _resultado_vazio("tipo_invalido")
    if not texto.strip():
        return _resultado_vazio("entrada_vazia")
    if len(texto) > LIMITE_CARACTERES:
        return _resultado_vazio("texto_excede_limite")

    normalizado = _sem_acentos(texto, preservar_tamanho=True)
    normalizado_publico = _sem_acentos(texto)
    composicao_interna, intervalos_composicao = _extrair_composicao(
        texto, normalizado)
    construcao = _extrair_lexico(
        texto, normalizado, _REGRAS_CONSTRUCAO, "construcao")
    acabamento = _extrair_lexico(
        texto, normalizado, _REGRAS_ACABAMENTO, "acabamento")

    avisos = []
    if _SEM_DADO.search(normalizado):
        avisos.append("declaracao_sem_dado")

    percentuais_soltos = [
        casamento for casamento in _RE_PERCENTUAL_SOLTO.finditer(normalizado)
        if not _sobrepoe(casamento.start(), casamento.end(), intervalos_composicao)
    ]
    if percentuais_soltos:
        avisos.append("percentual_sem_componente_reconhecido")

    por_parte = {}
    sem_percentual = False
    for item in composicao_interna:
        if item["percentual"] is None:
            sem_percentual = True
            continue
        por_parte.setdefault(item["parte_id"], 0.0)
        por_parte[item["parte_id"]] += float(item["percentual"])

    for parte_id, soma in sorted(por_parte.items()):
        if soma < 99.0:
            avisos.append("soma_percentual_incompleta:" + parte_id)
        elif soma > 101.0:
            avisos.append("soma_percentual_excedente:" + parte_id)
    if sem_percentual:
        avisos.append("fibra_sem_percentual")

    composicao = []
    for item in composicao_interna:
        publico = dict(item)
        publico.pop("_span", None)
        composicao.append(publico)

    campos_abstidos = [
        nome for nome, itens in (
            ("composicao", composicao),
            ("construcao", construcao),
            ("acabamento", acabamento),
        ) if not itens
    ]
    abstencao = len(campos_abstidos) == 3

    motivos_abstencao = []
    if abstencao:
        if "declaracao_sem_dado" in avisos:
            motivos_abstencao.append("declaracao_sem_dado")
        else:
            motivos_abstencao.append("nenhum_padrao_reconhecido")
        confianca = "nenhuma"
        explicacao = "nenhuma evidencia inequivoca foi reconhecida"
    elif any(a.startswith((
            "percentual_sem_", "soma_percentual_", "declaracao_sem_dado"
    )) for a in avisos):
        confianca = "baixa"
        explicacao = (
            "ha evidencias exatas, mas a etiqueta contem lacunas ou uma soma "
            "percentual inconsistente"
        )
    elif "fibra_sem_percentual" in avisos:
        confianca = "media"
        explicacao = (
            "a fibra foi declarada nominalmente, mas sem percentual para "
            "fechar a composicao"
        )
    else:
        confianca = "alta"
        explicacao = "as evidencias reconhecidas sao declaracoes textuais exatas"

    return {
        "versao": VERSAO_PARSER,
        "texto_normalizado": normalizado_publico,
        "composicao": composicao,
        "construcao": construcao,
        "acabamento": acabamento,
        "abstencao": abstencao,
        "motivos_abstencao": motivos_abstencao,
        "campos_abstidos": campos_abstidos,
        "confianca": confianca,
        "explicacao_confianca": explicacao,
        "avisos": list(dict.fromkeys(avisos)),
    }


# Alias curto para chamadores que tratam a operacao explicitamente como parse.
parsear_etiqueta = analisar_etiqueta

__all__ = [
    "LIMITE_CARACTERES", "VERSAO_DO_PARSER", "VERSAO_PARSER",
    "analisar_etiqueta", "parsear_etiqueta",
]
