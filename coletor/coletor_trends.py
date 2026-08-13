"""Coletor da perna de busca (Google Trends, §19).

Por que stdlib e nao `pytrends`: a biblioteca nao e oficial, quebra a cada
mudanca do Google, e exigiria `pip` no runner do Mac (que nao tem nem git nem
Python do sistema). Sao duas chamadas HTTP; controlar as duas a mao e mais
robusto e cumpre "dependencias minimas e justificadas".

O caminho e o mesmo que a interface do Trends usa:
  1. GET /trends/?geo=BR                      -> cookie NID
  2. GET /trends/api/explore?req={...}        -> token do widget TIMESERIES
  3. GET /trends/api/widgetdata/multiline     -> a serie semanal

Regras que este modulo cumpre:
  * K7 -- grupos de ate 5 termos com ANCORA FIXA comum a todos, senao os niveis
    nao sao comparaveis entre grupos (valor do Trends e relativo a consulta).
  * §19 -- backfill de 5 anos, geo BR, e metadados da consulta gravados junto
    de cada serie.
  * regra 4 -- so consulta `termo_busca` de linha com status=aprovado.
  * C3 -- afere volume e marca `sem_perna_busca` MEDIDO, em vez de chutado. Uma
    serie chapada no zero e a evidencia de termo morto, registrada com a
    consulta que a produziu.
  * regra 2 -- termo sem volume vira nulo declarado, nunca valor plausivel.

RODAR NO RUNNER RESIDENCIAL: o Google recusa IP de datacenter. Verificado em
30/07 -- responde 200 do IP de casa e bloqueia no Actions hospedado.
"""

import http.cookiejar
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import supabase_rest  # noqa: E402

BASE = "https://trends.google.com"
# Regra 7: a origem precisa saber quem somos. O UA de Chrome que havia aqui
# mascarava o coletor como navegador comum e contradizia a regra mais rígida do
# projeto. Se a interface privada do Trends exigir disfarce, ela deixou de ser
# uma fonte admissível; não burlamos a proteção para mantê-la viva.
UA = "CanarioBot/1.0 (projeto academico; contato: canarioch3@gmail.com)"
GEO = "BR"

# JANELA SEMANAL. A DIARIA FOI TENTADA EM 05/08 E REVERTIDA EM 06/08.
#
# O que motivou a tentativa: com o rotulo errado (veja `semana_iso`), a perna
# de busca parecia parar em 20/07 enquanto o editorial ia a 03/08, e a janela
# diaria (`today 3-m`) entregava dado ate ONTEM. Parecia trocar dez dias de
# atraso por zero.
#
# O que a medicao mostrou depois, e que derruba a troca:
#
# 1. NAO HAVIA FRESCURA A GANHAR. Contando semanas ISO fechadas, que e a
#    unidade que o app usa, as duas janelas chegam na MESMA semana -- 27/07,
#    medido no mesmo minuto. O `today 5-y` marca a semana pelo domingo 26/07,
#    que e a semana ISO de 27/07. O atraso aparente era o rotulo, nao a fonte.
#
# 2. A DIARIA CUSTA RESOLUCAO NO TERMO PEQUENO. O Trends normaliza 0-100 pelo
#    maior valor da janela; num recorte diario esse maximo e o maior DIA do
#    maior termo, e termo de volume baixo arredonda para zero na maioria dos
#    dias. Medido no mesmo termo, semanas em zero:
#
#                      semanal (227 sem)   diario (34 sem)
#      viscose_fluido        0,9%              73,5%
#      animal_print         10,6%              88,2%
#      algodao              54,2%              94,1%
#
#    Nao e que o semanal escondia serie vazia -- foi o que escrevi primeiro e
#    estava errado. E o diario que apaga sinal que existe. `viscose_fluido`
#    tem busca em 99% das semanas e sumiria.
#
# 3. E emendava mal. A janela diaria so alcanca ~269 dias, entao a serie
#    antiga (5 anos) e a nova ficavam em reguas diferentes, com degrau de ate
#    -95% no meio. Ver `series_busca_5y_legado`.
#
# Fica o semanal, com o rotulo consertado -- que era o defeito de verdade.
INTERVALO = "today 5-y"
ANCORA = "vestido floral"   # K7: fixa em todos os grupos
POR_GRUPO = 5               # teto do Trends
TZ = 180                    # minutos; BRT = UTC-3

# Medido em 30/07: com 12s entre requisicoes, 7 de 10 grupos tomaram 429 mesmo
# do IP residencial. O Trends limita por janela de tempo, nao por requisicao,
# entao o remedio e esperar de verdade -- e a coleta ser RETOMAVEL, para uma
# execucao que pega metade deixar a outra metade para a proxima.
ESPERA_ENTRE = 45.0
ESPERAS_429 = [90]
# Tres grupos concluiram antes do limite de janela do Google na primeira
# madrugada integrada. Planejamos esse teto e deixamos a rotacao completar a
# cobertura nos dias seguintes, em vez de provocar 429 e esperar em vao.
GRUPOS_POR_EXECUCAO = 3

# Abaixo disto a serie e considerada sem sinal utilizavel (C3). Media do valor
# bruto na janela inteira: o Trends normaliza 0-100, entao media < 1 significa
# que o termo praticamente nao aparece.
MEDIA_MINIMA = 1.0
HTTP_TRANSITORIOS = {429, 500, 502, 503}
FUSO_OPERACIONAL = ZoneInfo("America/Sao_Paulo")


class TrendsErro(Exception):
    pass


def motivo_http_transitorio(falhas):
    """Resume uma recusa HTTP conhecida sem esconder falha de outra natureza.

    O portao de saude sabe diferenciar um dia de recusa externa de zero sem
    explicacao. Antes desta funcao, o log dizia HTTP 429, mas a linha `saude`
    guardava apenas a lista de grupos; o motivo de topo sumia e o portao
    reportava falsamente "sem dizer por que".
    """
    if not falhas:
        return None
    codigos = []
    for falha in falhas:
        achado = re.search(r"\bHTTP\s+(\d{3})\b", str(falha.get("erro") or ""),
                           flags=re.IGNORECASE)
        if not achado:
            return None
        codigo = int(achado.group(1))
        if codigo not in HTTP_TRANSITORIOS:
            return None
        codigos.append(codigo)
    resumo = "/".join(str(c) for c in sorted(set(codigos)))
    return "http {} em todos os {} grupos apos backoff".format(
        resumo, len(falhas))


def alertas_com_motivo_http(alertas):
    """Deriva a causa de topo a partir do detalhe, inclusive em linha antiga."""
    novos = dict(alertas or {})
    motivo = motivo_http_transitorio(novos.get("grupos_que_falharam") or [])
    if motivo:
        novos["erro"] = motivo
    return novos


def data_operacional(agora=None):
    agora = agora or datetime.now(FUSO_OPERACIONAL)
    return agora.astimezone(FUSO_OPERACIONAL).date()


def reconsolidar_saude_existente(hoje):
    """Repara apenas o diagnostico persistido; nao toca no Google Trends."""
    filtro = ("?data=eq.{}&fonte=eq.busca&marca_id=is.null&"
              "select=data,fonte,marca_id,visitados,gravados,itens,"
              "pct_campos_ok,alertas&limit=1").format(hoje.isoformat())
    linhas = supabase_rest.selecionar("saude", filtro)
    if not linhas:
        print("ERRO: nao existe saude da busca para {}.".format(hoje),
              file=sys.stderr)
        return 1
    linha = dict(linhas[0])
    alertas = alertas_com_motivo_http(linha.get("alertas"))
    if not alertas.get("erro"):
        print("ERRO: a linha nao contem somente recusas HTTP transitórias.",
              file=sys.stderr)
        return 1
    linha["alertas"] = alertas
    supabase_rest.upsert("saude", [linha], on_conflict="data,fonte,marca_id")
    print("Saude da busca reconsolidada sem nova consulta: {}.".format(
        alertas["erro"]), file=sys.stderr)
    return 0


def semana_iso(quando):
    """Segunda ISO da semana que o Trends marcou com a data `quando`.

    ESTE E O BUG DE SEIS DIAS QUE NUNCA LEVANTOU EXCECAO.
    ====================================================

    A versao antiga fazia:

        semana = quando - timedelta(days=quando.weekday())   # "segunda ISO"

    O Trends marca cada semana pelo DOMINGO em que ela comeca. `weekday()` de
    domingo e 6, entao essa linha subtraia seis dias e jogava o ponto para a
    segunda ANTERIOR -- fora do periodo que ele mede. A semana que o Google
    diz ser 26/07 a 01/08 era gravada como "semana de 20/07".

    O estrago tem duas partes, e a segunda e a pior:

    1. O atraso parecia muito maior do que era. Medindo contra o rotulo
       deslocado, a perna de busca parecia 16 dias atras do editorial. Contando
       semanas ISO fechadas, as duas pernas alcancam a mesma semana.

    2. AS DUAS PERNAS COMPARAVAM PERIODOS DIFERENTES. O editorial usa
       `date_trunc('week')` do Postgres, que da segunda ISO de verdade: ali
       "semana de 20/07" e 20 a 26 de julho. Na busca, o mesmo rotulo era 26/07
       a 01/08. Mesmo nome, seis dias de deslocamento, UM dia em comum. A §22
       exige duas pernas concordando na mesma semana e vinha, em silencio,
       cruzando semanas quase disjuntas -- em toda leitura do app, desde
       sempre. Nao aparece em log nenhum: o numero existe, so mede outra coisa.

    O conserto e andar para FRENTE ate a segunda, e nao para tras: a semana do
    Google (domingo S a sabado S+6) e a semana ISO que comeca em S+1 dividem
    seis dos sete dias. Antes era um.

    Sobra um dia de imprecisao, e ele e inerente -- o Google conta a semana de
    domingo a sabado e o resto do projeto de segunda a domingo. Nao da para
    zerar sem trocar de fonte; da para nao mentir sobre ele, e por isso o
    `meta` grava `alinhamento`.
    """
    return quando + timedelta(days=(7 - quando.weekday()) % 7)


def ultima_semana_fechada(hoje):
    """Segunda da ultima semana ISO que ja terminou.

    Serve de regua para "em dia": o corte antigo era `hoje - 2 semanas`, um
    numero escolhido a mao para compensar o atraso do Trends. Com a semana
    montada a partir do dia, a regua vira exata -- e a fonte, e nao o relogio,
    diz qual e o teto possivel.
    """
    return hoje - timedelta(days=hoje.weekday() + 7)


def corte_de_frescura(hoje):
    """Semana que já é razoável cobrar do Google.

    Segunda a quarta toleram a publicação atrasar uma semana. De quinta em
    diante, a última semana encerrada no domingo já teve pelo menos três dias
    para aparecer. O corte anterior tolerava uma semana inteira todos os dias
    e chamava 27/07 de atual em 13/08.
    """
    fechada = ultima_semana_fechada(hoje)
    return fechada - timedelta(weeks=1) if hoje.weekday() <= 2 else fechada


class Trends(object):
    def __init__(self):
        self.cj = http.cookiejar.CookieJar()
        self.op = urllib.request.build_opener(
            urllib.request.HTTPCookieProcessor(self.cj))
        self._ultima = 0.0

    def _ritmo(self):
        espera = ESPERA_ENTRE - (time.monotonic() - self._ultima)
        if espera > 0:
            time.sleep(espera)
        self._ultima = time.monotonic()

    def _get(self, url, referer=None):
        cabecalhos = {"User-Agent": UA, "Accept-Language": "pt-BR,pt;q=0.9"}
        if referer:
            cabecalhos["Referer"] = referer
        ultimo = None
        for i, espera in enumerate([0] + ESPERAS_429):
            if espera:
                time.sleep(espera)
            self._ritmo()
            try:
                r = self.op.open(urllib.request.Request(url, headers=cabecalhos),
                                 timeout=45)
                return r.read().decode("utf-8", "replace")
            except urllib.error.HTTPError as e:
                ultimo = "HTTP {}".format(e.code)
                if e.code not in (429, 500, 502, 503):
                    raise TrendsErro(ultimo)
            except Exception as e:
                ultimo = "{}: {}".format(type(e).__name__, str(e)[:80])
        raise TrendsErro("falhou apos {} tentativas ({})".format(
            len(ESPERAS_429) + 1, ultimo))

    def aquecer(self):
        """Pega o cookie NID; sem ele o explore recusa."""
        self._get(BASE + "/trends/?geo=" + GEO)

    @staticmethod
    def _json(texto):
        # A resposta vem prefixada com )]}' para nao ser executavel como JS.
        i = texto.find("{")
        if i < 0:
            raise TrendsErro("resposta sem JSON")
        return json.loads(texto[i:])

    def token_timeseries(self, termos, intervalo):
        req = {"comparisonItem": [{"keyword": t, "geo": GEO, "time": intervalo}
                                  for t in termos],
               "category": 0, "property": ""}
        url = (BASE + "/trends/api/explore?hl=pt-BR&tz={}&req={}".format(
            TZ, urllib.parse.quote(json.dumps(req, separators=(",", ":")))))
        d = self._json(self._get(url, BASE + "/trends/explore"))
        for w in d.get("widgets", []):
            if w.get("id") == "TIMESERIES":
                return w.get("token"), w.get("request")
        raise TrendsErro("explore nao devolveu widget TIMESERIES")

    def serie(self, termos, hoje=None):
        """Devolve {termo: [(semana_iso, valor), ...]} para o grupo."""
        token, requisicao = self.token_timeseries(termos, INTERVALO)
        url = (BASE + "/trends/api/widgetdata/multiline"
               "?hl=pt-BR&tz={}&req={}&token={}".format(
                   TZ,
                   urllib.parse.quote(json.dumps(requisicao, separators=(",", ":"))),
                   urllib.parse.quote(token)))
        d = self._json(self._get(url, BASE + "/trends/explore"))
        pontos = (d.get("default") or {}).get("timelineData") or []
        por_termo = dict((t, []) for t in termos)
        for p in pontos:
            if p.get("isPartial"):
                continue  # semana ainda aberta: nao entra na serie
            try:
                quando = datetime.fromtimestamp(int(p["time"]), timezone.utc).date()
            except (KeyError, ValueError, OSError):
                continue
            valores = p.get("value") or []
            for i, termo in enumerate(termos):
                if i < len(valores) and valores[i] is not None:
                    por_termo[termo].append((semana_iso(quando),
                                             float(valores[i])))

        # GUARDA DE GRANULARIDADE. `today 5-y` vem em semanas hoje, mas quem
        # decide isso e o Google. Se ele passar a devolver dias, cada ponto
        # viraria uma "semana" e a serie ficaria sete vezes mais densa, com
        # valores de outra natureza -- e o portao de saude leria isso como
        # coleta melhorando. Melhor estourar dizendo o que mudou: foi o
        # silencio que deixou o erro de seis dias sobreviver.
        amostra = sorted(next((d for d in por_termo.values() if len(d) > 1), []))
        if amostra:
            passo = (amostra[1][0] - amostra[0][0]).days
            if passo != 7:
                raise TrendsErro(
                    "Trends devolveu passo de {} dia(s), e nao semanal, para "
                    "{!r}. A perna de busca grava semana ISO; com outro passo "
                    "o rotulo deixa de bater com o do editorial e a §22 volta "
                    "a comparar periodos diferentes.".format(passo, INTERVALO))
        return dict((t, sorted(pts)) for t, pts in por_termo.items())


def grupos_de_termos(termos_aprovados):
    """K7: ancora fixa + 4 novos por grupo."""
    fila = [t for t in termos_aprovados if t["termo_busca"] != ANCORA]
    tamanho = POR_GRUPO - 1
    return [fila[i:i + tamanho] for i in range(0, len(fila), tamanho)]


def fila_por_defasagem(aprovados, em_dia, nunca, modo=""):
    """Ordena os termos por quanto tempo faz que a serie de busca nao anda.

    Devolve `(fila, modo)`. Termo sem serie nenhuma vem primeiro (defasagem
    infinita), mas NAO bloqueia os demais -- foi exatamente esse o defeito que
    congelou a perna duas vezes. Quando todo mundo esta em dia, a fila volta a
    ser a taxonomia inteira, que e a cadencia semanal que a §19 pede.
    """
    if modo == "semanal":
        return sorted(aprovados, key=lambda t: t["id"]), "semanal"

    alvos = [t for t in aprovados if t["id"] not in em_dia]
    if not alvos:
        return [], "em_dia"

    # Sem serie na frente; entre os demais, ordem estavel por id para o lote do
    # dia ser deterministico e auditavel.
    alvos.sort(key=lambda t: (t["id"] not in nunca, t["id"]))
    return alvos, "defasagem"


def planejar_grupos(grupos, hoje, limite=GRUPOS_POR_EXECUCAO, tentativa=0):
    """Seleciona um lote diario deterministico e rotativo de grupos.

    O deslocamento pelo proprio limite faz tres lotes consecutivos cobrirem
    nove grupos sem sobreposicao. Para outros totais, permanece deterministico
    e nunca envia mais consultas do que o orcamento medido suporta.
    """
    if limite <= 0 or len(grupos) <= limite:
        return grupos
    inicio = (hoje.toordinal() * limite + tentativa * limite) % len(grupos)
    return [grupos[(inicio + i) % len(grupos)] for i in range(limite)]


def combinar_saude_busca(anterior, tentativa, atual):
    """Acumula tentativas do dia sem duplicar uma reexecucao.

    A chave da tentativa transforma a atualizacao em idempotente: repetir a
    recuperacao 1 substitui a execucao 1, em vez de inflar os totais. Linhas
    gravadas antes desta estrutura sao preservadas como tentativa 0.
    """
    anterior = anterior or {}
    alertas_anteriores = dict(anterior.get("alertas") or {})
    execucoes = dict(alertas_anteriores.get("execucoes") or {})
    if anterior and not execucoes:
        chave_anterior = str(alertas_anteriores.get("tentativa", 0))
        execucoes[chave_anterior] = {
            "tentados": int(anterior.get("visitados") or 0),
            "responderam": int(anterior.get("gravados") or 0),
            "itens": int(anterior.get("itens") or 0),
            "grupos_que_falharam": (
                alertas_anteriores.get("grupos_que_falharam") or []),
        }

    alertas_atuais = dict(atual.get("alertas") or {})
    execucoes[str(tentativa)] = {
        "tentados": int(atual.get("visitados") or 0),
        "responderam": int(atual.get("gravados") or 0),
        "itens": int(atual.get("itens") or 0),
        "grupos_que_falharam": (
            alertas_atuais.get("grupos_que_falharam") or []),
    }

    tentados = sum(int(e.get("tentados") or 0) for e in execucoes.values())
    responderam = sum(int(e.get("responderam") or 0)
                      for e in execucoes.values())
    itens = sum(int(e.get("itens") or 0) for e in execucoes.values())
    falhas = []
    for chave in sorted(execucoes, key=lambda x: int(x)):
        for falha in execucoes[chave].get("grupos_que_falharam") or []:
            registro = dict(falha)
            registro["tentativa"] = int(chave)
            falhas.append(registro)

    alertas_atuais["tentativa"] = tentativa
    alertas_atuais["execucoes"] = execucoes
    alertas_atuais["grupos_que_falharam"] = falhas or None
    alertas_atuais["grupos_planejados"] = tentados
    return {
        "visitados": tentados,
        "gravados": responderam,
        "itens": itens,
        "pct_campos_ok": (round(responderam / float(tentados), 3)
                          if tentados else None),
        "alertas": alertas_atuais,
    }


def _veredito(pontos, media_ancora):
    """C3: decide sem_perna_busca a partir do que foi MEDIDO."""
    if not pontos:
        return "sim", "o Trends nao devolveu serie para este termo_busca"
    media = sum(v for _, v in pontos) / len(pontos)
    zeros = sum(1 for _, v in pontos if v <= 0) / float(len(pontos))
    # Duas formas de estar morto: nivel baixo demais, ou serie quase toda zerada
    # com picos isolados (ruido, nao sinal).
    if media < MEDIA_MINIMA:
        sem_perna = "sim"
        detalhe = "chapada: media {:.2f} em {} semanas (minimo {})".format(
            media, len(pontos), MEDIA_MINIMA)
    elif zeros > 0.8:
        sem_perna = "sim"
        detalhe = "esparsa: {:.0%} das {} semanas em zero".format(zeros, len(pontos))
    else:
        sem_perna = "nao"
        detalhe = "media {:.1f} em {} semanas, {:.0%} de semanas em zero".format(
            media, len(pontos), zeros)
    if media_ancora:
        detalhe += "; {:.2f}x a ancora".format(media / media_ancora)
    return sem_perna, detalhe


def gravar_grupo(dados_por_termo, hoje, agora):
    """Grava as series e os vereditos de UM grupo.

    Grava por grupo, e nao no fim de tudo: o Trends pode bloquear no meio, e
    perder nove grupos por causa do decimo seria repetir a perda silenciosa que
    a gravacao por delta (B3) existe para evitar.
    """
    linhas, atualizacoes = [], []
    for termo_id, dados in dados_por_termo.items():
        pontos = dados["pontos"]
        # `alinhamento` fica registrado porque a regra 3 pede o caminho ate a
        # origem, e aqui sobra um dia de imprecisao que nao da para esconder:
        # o Google conta a semana de domingo a sabado, o resto do projeto de
        # segunda a domingo. O ponto e movido para a segunda seguinte, que
        # divide seis dos sete dias com a semana medida.
        meta = {"fonte": "google_trends", "geo": GEO, "intervalo": INTERVALO,
                "granularidade": "semanal",
                "alinhamento": "domingo do Trends -> segunda ISO seguinte "
                               "(6 de 7 dias em comum)",
                "ancora": ANCORA, "grupo": dados["grupo"],
                "ancora_media_no_grupo": dados["media_ancora"],
                "termo_busca": dados["termo_busca"], "coletado_em": agora}
        for semana, valor in pontos:
            linhas.append({
                "termo_id": termo_id, "segmento": "feminino_casual_br",
                "fonte": "busca", "semana": semana.isoformat(),
                "valor_bruto": valor, "z": None, "n_amostra": None, "meta": meta,
            })
        sem_perna, detalhe = _veredito(pontos, dados["media_ancora"])
        atualizacoes.append({"id": termo_id, "sem_perna_busca": sem_perna,
                             "volume_verificado_em": hoje.isoformat(),
                             "volume_detalhe": detalhe})

    for i in range(0, len(linhas), 500):
        supabase_rest.upsert("series_semanais", linhas[i:i + 500],
                             on_conflict="termo_id,segmento,fonte,semana")

    # Nao ha limpeza de escala aqui, e isso e de proposito. A tentativa da
    # janela diaria (05/08) precisava apagar o historico porque as duas reguas
    # nao emendavam; com uma janela so, cada consulta cobre a serie inteira e o
    # upsert reescreve tudo na mesma regua. Ver `series_busca_5y_legado`.

    # UPDATE, nao upsert: o termo ja existe e a linha aqui e parcial.
    for a in atualizacoes:
        supabase_rest.atualizar(
            "termos", "id=eq." + urllib.parse.quote(a["id"]),
            {"sem_perna_busca": a["sem_perna_busca"],
             "volume_verificado_em": a["volume_verificado_em"],
             "volume_detalhe": a["volume_detalhe"]})
    return len(linhas), [a for a in atualizacoes if a["sem_perna_busca"] == "sim"]


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    if os.environ.get("TRENDS_SOMENTE_RECONSOLIDAR", "").lower() in {
            "1", "true", "yes"}:
        return reconsolidar_saude_existente(data_operacional())

    try:
        tentativa = max(0, int(os.environ.get("TRENDS_TENTATIVA", "0") or 0))
    except ValueError:
        print("ERRO: TRENDS_TENTATIVA deve ser um inteiro.", file=sys.stderr)
        return 1

    # regra 4: so termo aprovado, e so com termo_busca preenchido.
    aprovados = [t for t in supabase_rest.selecionar(
        "termos", "?status=eq.aprovado&select=id,termo_busca,dimensao&order=id")
        if (t.get("termo_busca") or "").strip()]
    if not aprovados:
        print("Nenhum termo aprovado com termo_busca. Nada a coletar.", file=sys.stderr)
        return 0

    # PRIORIDADE POR DEFASAGEM, e nao dois modos exclusivos.
    #
    # O QUE QUEBROU DUAS VEZES:
    #
    # 1o (13/07, descoberto 19 dias depois): so existia o modo `backfill`, que
    #    pula termo que JA TEM serie. Como o filtro era permanente, os termos
    #    ja cobertos nunca mais eram consultados e a perna congelou.
    #
    # 2o (20/07, descoberto em 05/08): a correcao criou o modo `semanal`, mas
    #    condicionado a `backfill` ter terminado -- e ele nunca termina. Medido:
    #    36 dos 40 termos ja tinham 261 pontos cada (cinco anos de historia), e
    #    QUATRO termos sem serie (`reta_wide`, `romantico`, `saia`, `short`)
    #    prendiam o modo em backfill. Com `aprovados` filtrado para esses
    #    quatro, sobrava UM grupo, esse grupo apanhava de 429, e os outros 36
    #    ficavam parados. Quatro termos travando trinta e seis.
    #
    # A licao das duas vezes e a mesma: `tem serie` nao e a pergunta certa. A
    # pergunta e HA QUANTO TEMPO. Agora nao existe modo: existe uma fila
    # ordenada por defasagem, e o orcamento diario come dela de cima para
    # baixo. Termo sem serie nenhuma entra na frente (defasagem infinita), mas
    # nao BLOQUEIA -- se ele nao responde, a rotacao do dia seguinte serve
    # outro. `TRENDS_MODO=semanal` continua existindo para forcar a mao.
    total_aprovados = len(aprovados)
    # Guardado ANTES de `aprovados` virar a fila do dia: o relatorio de saude
    # precisa do universo inteiro, nao do lote.
    ids_aprovados = {t["id"] for t in aprovados}
    modo = os.environ.get("TRENDS_MODO", "").strip().lower()
    hoje = data_operacional()

    # Em dia = cobre a ultima semana ISO fechada, com uma semana de tolerancia
    # para o atraso de publicacao do Google.
    #
    # O corte antigo era `hoje - 2 semanas` e nao era o defeito: o defeito era
    # o rotulo. Com o deslocamento de seis dias (veja `semana_iso`), a ultima
    # semana gravada aparecia como 20/07 enquanto o corte pedia 22/07, entao
    # TODO termo parecia atrasado TODO dia e o coletor gastava execucao inteira
    # reconsultando quem ja estava em dia. Consertado o rotulo, a comparacao
    # passa a fazer sentido.
    #
    # A tolerancia de uma semana fica porque o Google publica a semana fechada
    # com alguns dias de atraso: no comeco da semana, cobrar a ultima fechada
    # marcaria todo mundo como defasado por dois ou tres dias, sem que houvesse
    # nada a coletar.
    #
    # A cobertura vem da view `cobertura_da_busca`, uma linha por termo. Fazer
    # isso no cliente NAO funciona: o PostgREST corta em 1000 linhas por
    # resposta e `selecionar()` nao pagina, entao puxar `series_semanais`
    # inteira fez o coletor concluir "36 termos sem serie" quando eram QUATRO.
    corte = corte_de_frescura(hoje).isoformat()
    em_dia, nunca = set(), set()
    for r in supabase_rest.selecionar(
            "cobertura_da_busca", "?select=termo_id,ultima_semana"):
        if not r.get("ultima_semana"):
            nunca.add(r["termo_id"])
        elif r["ultima_semana"] >= corte:
            em_dia.add(r["termo_id"])

    aprovados, modo = fila_por_defasagem(aprovados, em_dia, nunca, modo)
    print("Fila por defasagem ({}): {} de {} termos a consultar "
          "({} sem serie nenhuma, {} em dia).".format(
              modo, len(aprovados), total_aprovados, len(nunca),
              len(em_dia)), file=sys.stderr)
    grupos_totais = grupos_de_termos(aprovados)
    grupos = planejar_grupos(grupos_totais, hoje, tentativa=tentativa)
    print("Termos aprovados: {} | grupos de {}: {} planejados de {} | "
          "tentativa: {} | ancora fixa: {!r}".format(
              len(aprovados), POR_GRUPO, len(grupos), len(grupos_totais),
              tentativa, ANCORA),
          file=sys.stderr)

    # Fonte semanal realmente em dia: não abre cookie, não chama endpoint e
    # não fabrica uma falha por ter feito zero pedidos. A saúde registra o
    # skip deliberado e o motor pode processar as outras fontes atuais.
    if not grupos:
        linha = {
            "data": hoje.isoformat(), "fonte": "busca", "marca_id": None,
            "visitados": 0, "gravados": 0, "itens": 0,
            "pct_campos_ok": None,
            "alertas": {
                "adiado_por_cadencia": True,
                "motivo": "todas as series de busca estao em dia",
                "corte_de_frescura": corte,
                "termos_em_dia": len(em_dia),
                "termos_aprovados": total_aprovados,
            },
        }
        supabase_rest.upsert("saude", [linha],
                             on_conflict="data,fonte,marca_id")
        print("Busca em dia ate o corte {}: nenhuma consulta ao Google."
              .format(corte), file=sys.stderr)
        return 0

    id_da_ancora = next((x["id"] for x in aprovados
                         if x["termo_busca"] == ANCORA), None)
    falhas = []
    ancora_pontos = None
    total_pontos = 0
    mortos = []
    termos_com_serie = set()
    grupos_tentados = 0
    grupos_respondidos = 0

    t = Trends()
    try:
        t.aquecer()
        aquecido = True
    except TrendsErro as e:
        aquecido = False
        grupos_tentados = 1
        falhas.append({"grupo": 0, "erro": str(e), "etapa": "aquecimento"})
        print("  aquecimento: FALHOU ({})".format(e), file=sys.stderr)
    agora = datetime.now(timezone.utc).isoformat()

    for i, grupo in enumerate(grupos if aquecido else [], 1):
        grupos_tentados += 1
        consulta = [ANCORA] + [x["termo_busca"] for x in grupo]
        try:
            series = t.serie(consulta, hoje)
        except TrendsErro as e:
            falhas.append({"grupo": i, "erro": str(e)})
            print("  grupo {}/{}: FALHOU ({})".format(i, len(grupos), e),
                  file=sys.stderr)
            # 429/5xx vem do mesmo serviço, não do termo. Insistir nos outros
            # grupos depois que o backoff falhou só amplia o bloqueio.
            if re.search(r"\bHTTP\s+(?:429|5\d\d)\b", str(e), re.IGNORECASE):
                print("  circuito aberto: os demais grupos ficam para a "
                      "proxima janela.", file=sys.stderr)
                break
            continue

        grupos_respondidos += 1

        # A media da ancora NESTE grupo e o que torna os grupos comparaveis: o
        # Trends normaliza 0-100 dentro de cada consulta, entao um termo enorme
        # no grupo comprime os demais. Guardar a ancora deixa o motor converter
        # tudo para unidade relativa a ela -- e a razao de existir o K7.
        pontos_ancora = series.get(ANCORA) or []
        media_ancora = (sum(v for _, v in pontos_ancora) / len(pontos_ancora)
                        if pontos_ancora else None)
        if ancora_pontos is None and pontos_ancora:
            ancora_pontos = pontos_ancora

        dados_grupo = {}
        for termo_row in grupo:
            tb = termo_row["termo_busca"]
            if series.get(tb):
                termos_com_serie.add(termo_row["id"])
            dados_grupo[termo_row["id"]] = {
                "termo_busca": tb, "pontos": series.get(tb) or [],
                "grupo": i, "media_ancora": media_ancora}

        gravados, sem_perna = gravar_grupo(dados_grupo, hoje, agora)
        total_pontos += gravados
        mortos.extend(a["id"] for a in sem_perna)
        print("  grupo {}/{}: {} termos, {} pontos gravados"
              " (ancora media {}){}".format(
                  i, len(grupos), len(grupo), gravados,
                  "{:.1f}".format(media_ancora) if media_ancora else "-",
                  "  sem perna: " + ", ".join(a["id"] for a in sem_perna)
                  if sem_perna else ""), file=sys.stderr)

    # TERMO SEM VOLUME DE BUSCA PARA DE CONSUMIR ORCAMENTO.
    #
    # `mortos` era so' reportado no log e na saude, nunca gravado -- entao um
    # termo que o Trends nao cobre era redescoberto e esquecido toda execucao,
    # ocupando lugar na fila para sempre. Agora a descoberta vira fato na
    # taxonomia. Nao e' exclusao: o termo continua aprovado e continua tendo as
    # outras pernas; so' deixa de ser cobrado da perna de busca.
    #
    # `nao` tambem e' gravado, e de proposito: um termo que RESPONDEU tem de
    # sair de `pendente`, senao nunca se distingue "ja testamos e tem" de
    # "ainda nao testamos".
    #
    # ATUALIZA, NUNCA FAZ UPSERT. O upsert com `{id, sem_perna_busca}` manda
    # uma linha inteira com o resto nulo: o Postgres recusou por `rotulo` NOT
    # NULL e a taxonomia se salvou por causa da constraint -- mas o corpo
    # enviado ja trazia `status` no default `proposto`, ou seja, um upsert bem
    # sucedido teria DESAPROVADO os termos. Medido em 05/08 na primeira
    # execucao. Campo isolado se escreve com PATCH.
    def declarar(ids, valor):
        for tid in sorted(ids):
            # O filtro vai SEM o "?": `atualizar` ja o prefixa.
            supabase_rest.atualizar(
                "termos", "id=eq.{}".format(tid), {"sem_perna_busca": valor})

    sem_volume = set(mortos)
    declarar(sem_volume, "sim")
    declarar(termos_com_serie - sem_volume, "nao")
    if sem_volume or termos_com_serie:
        print("Perna de busca declarada em {} termos ({} sem volume).".format(
            len(sem_volume | termos_com_serie), len(sem_volume)),
            file=sys.stderr)

    # A propria ancora e um termo da taxonomia (`floral`): a serie dela tambem
    # precisa ser gravada, senao o termo mais usado do sistema fica sem perna.
    if id_da_ancora and ancora_pontos:
        termos_com_serie.add(id_da_ancora)
        gravados, _ = gravar_grupo(
            {id_da_ancora: {"termo_busca": ANCORA, "pontos": ancora_pontos,
                            "grupo": 0, "media_ancora": None}}, hoje, agora)
        total_pontos += gravados
        print("  ancora {!r}: {} pontos gravados".format(ANCORA, gravados),
              file=sys.stderr)

    # --- saude (§20): UMA linha por dia para a fonte de busca ---
    #
    # ISTO NAO EXISTIA, e e por isso que a perna de busca pode congelar em
    # 13/07 e ninguem perceber ate 01/08. `saude` so tinha `varejo` e
    # `editorial`; o que nao se mede nao se sabe que parou.
    #
    # `visitados` = grupos tentados, `gravados` = grupos que responderam.
    # A divergencia entre os dois E o alerta: com 429 do Google, um dia em que
    # nenhum grupo passa fica visivel na hora.
    tentados = grupos_tentados
    # Grupos que o circuito deliberadamente adiou não contam como tentativa.
    responderam = grupos_respondidos
    recusa_http = motivo_http_transitorio(falhas) if not responderam else None
    # Quem ja tinha serie (universo menos os que nunca coletaram) mais quem
    # coletou agora. `ja_tem` morreu junto com os dois modos; usar o nome
    # antigo aqui passou pelo `ast.parse` e so estourou no runner, porque
    # NameError e erro de execucao, nao de sintaxe.
    cobertura = len((ids_aprovados - nunca) | termos_com_serie)
    atual = {
        "visitados": tentados,
        "gravados": responderam,
        "itens": total_pontos,
        "pct_campos_ok": (round(responderam / float(tentados), 3)
                          if tentados else None),
        "alertas": alertas_com_motivo_http({
            "erro": recusa_http,
            "modo": modo,
            "tentativa": tentativa,
            "grupos_que_falharam": falhas or None,
            "grupos_planejados": len(grupos),
            "grupos_totais": len(grupos_totais),
            "grupos_adiados_por_orcamento": len(grupos_totais) - len(grupos),
            "termos_sem_perna_de_busca": sorted(mortos) or None,
            "termos_com_serie": cobertura,
            "termos_aprovados": total_aprovados,
            "semana_mais_recente": hoje.isoformat(),
        }),
    }
    anteriores = supabase_rest.selecionar(
        "saude", "?data=eq.{}&fonte=eq.busca&marca_id=is.null&"
        "select=visitados,gravados,itens,alertas&limit=1".format(
            hoje.isoformat()))
    consolidada = combinar_saude_busca(
        anteriores[0] if anteriores else None, tentativa, atual)
    consolidada.update({
        "data": hoje.isoformat(), "fonte": "busca", "marca_id": None,
    })
    supabase_rest.upsert(
        "saude", [consolidada], on_conflict="data,fonte,marca_id")

    print("\nTotal: {} pontos de serie.".format(total_pontos), file=sys.stderr)
    print("Sem perna de busca ({}): {}".format(
        len(mortos), ", ".join(sorted(mortos)) or "nenhum"), file=sys.stderr)
    if falhas:
        print("Grupos que falharam: {}".format(falhas), file=sys.stderr)
    # Recusa HTTP conhecida fica a cargo do portao de saude: um dia vira aviso
    # e tres dias seguidos bloqueiam. Sair 1 aqui disparava imediatamente outra
    # bateria de 12 chamadas contra o mesmo 429 e deixava a run vermelha mesmo
    # quando a serie anterior continuava valida. Erro desconhecido permanece
    # falha dura.
    if tentados and not responderam:
        if recusa_http:
            print("AVISO: {}. A serie anterior foi preservada; o portao decide "
                  "pela persistencia.".format(recusa_http), file=sys.stderr)
            return 0
        print("ERRO: nenhum grupo respondeu. A perna de busca nao avancou hoje.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
