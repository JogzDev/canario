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
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import supabase_rest  # noqa: E402

BASE = "https://trends.google.com"
UA = ("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0 Safari/537.36")
GEO = "BR"

# JANELA DIARIA, E NAO "today 5-y". O PORQUE, MEDIDO EM 05/08:
#
# O Trends escolhe a granularidade pelo TAMANHO da janela, e nao pelo que se
# pede. Sondando o mesmo termo em cinco janelas no mesmo minuto:
#
#   today 5-y   semanal   ultima semana completa: 26/07
#   today 12-m  semanal   ultima semana completa: 26/07
#   today 3-m   DIARIO    ultimo dia completo:    05/08
#   today 1-m   DIARIO    ultimo dia completo:    05/08
#   240 dias    DIARIO    241 pontos, 34 semanas ISO completas
#
# A janela semanal chega com ~10 dias de atraso; a diaria chega em ONTEM. E
# 240 dias ainda vem em dias, o que da 34 semanas ISO completas -- quase tres
# vezes as 12 que a §21 consome na janela movel do z. Entao a perna de busca
# passa a ser montada por nos, dia a dia, em semana ISO.
#
# O GANHO MAIOR NAO E A FRESCURA, E O ALINHAMENTO. Veja `semanas_iso` abaixo.
DIAS_DA_JANELA = 240
ANCORA = "vestido floral"   # K7: fixa em todos os grupos
POR_GRUPO = 5               # teto do Trends
TZ = 180                    # minutos; BRT = UTC-3

# Medido em 30/07: com 12s entre requisicoes, 7 de 10 grupos tomaram 429 mesmo
# do IP residencial. O Trends limita por janela de tempo, nao por requisicao,
# entao o remedio e esperar de verdade -- e a coleta ser RETOMAVEL, para uma
# execucao que pega metade deixar a outra metade para a proxima.
ESPERA_ENTRE = 45.0
ESPERAS_429 = [60, 180, 420]
# Tres grupos concluiram antes do limite de janela do Google na primeira
# madrugada integrada. Planejamos esse teto e deixamos a rotacao completar a
# cobertura nos dias seguintes, em vez de provocar 429 e esperar em vao.
GRUPOS_POR_EXECUCAO = 3

# Abaixo disto a serie e considerada sem sinal utilizavel (C3). Media do valor
# bruto na janela inteira: o Trends normaliza 0-100, entao media < 1 significa
# que o termo praticamente nao aparece.
MEDIA_MINIMA = 1.0


class TrendsErro(Exception):
    pass


def janela(hoje):
    """Intervalo diario que o Trends aceita: 'AAAA-MM-DD AAAA-MM-DD'."""
    return "{} {}".format((hoje - timedelta(days=DIAS_DA_JANELA)).isoformat(),
                          hoje.isoformat())


def semanas_iso(pontos_diarios):
    """Agrega (dia, valor) em (segunda ISO, media), so com a semana fechada.

    ESTA FUNCAO EXISTE POR UM ERRO DE SEIS DIAS QUE NUNCA LEVANTOU EXCECAO.
    ================================================================

    A versao antiga lia a serie SEMANAL do Trends e fazia:

        semana = quando - timedelta(days=quando.weekday())   # "segunda ISO"

    O Trends marca cada semana pelo DOMINGO em que ela comeca. `weekday()` de
    domingo e 6, entao essa linha subtraia seis dias e jogava o ponto para a
    segunda ANTERIOR -- fora do periodo que ele mede. A semana que o Google
    diz ser 26/07 a 01/08 era gravada como "semana de 20/07".

    O estrago tem duas partes, e a segunda e a pior:

    1. O atraso parecia muito maior do que era. Medindo contra o rotulo
       deslocado, a perna de busca parecia 16 dias atras do editorial. O
       atraso real, do fim do periodo coberto ate hoje, era de 4 dias.

    2. AS DUAS PERNAS COMPARAVAM PERIODOS DIFERENTES. O editorial usa
       `date_trunc('week')` do Postgres, que da segunda ISO de verdade: ali
       "semana de 20/07" e 20 a 26 de julho. Na busca, o mesmo rotulo era 26/07
       a 01/08. Mesmo nome, seis dias de deslocamento, UM dia em comum. A §22
       exige duas pernas concordando na mesma semana e vinha, em silencio,
       cruzando semanas quase disjuntas -- em toda leitura do app, desde
       sempre. Nao aparece em log nenhum: o numero existe, so mede outra coisa.

    Montando a semana a partir do dia, o rotulo passa a ser a segunda ISO de
    verdade, identica a do editorial. Nao ha o que alinhar depois.

    So entra semana com os SETE dias presentes: semana pela metade tem media
    de outra natureza e entraria na janela do z como se fosse comparavel.
    """
    baldes = {}
    for dia, valor in pontos_diarios:
        baldes.setdefault(dia - timedelta(days=dia.weekday()), []).append(valor)
    return sorted((seg, sum(vs) / len(vs))
                  for seg, vs in baldes.items() if len(vs) == 7)


def ultima_semana_fechada(hoje):
    """Segunda da ultima semana ISO que ja terminou.

    Serve de regua para "em dia": o corte antigo era `hoje - 2 semanas`, um
    numero escolhido a mao para compensar o atraso do Trends. Com a semana
    montada a partir do dia, a regua vira exata -- e a fonte, e nao o relogio,
    diz qual e o teto possivel.
    """
    return hoje - timedelta(days=hoje.weekday() + 7)


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
        hoje = hoje or date.today()
        token, requisicao = self.token_timeseries(termos, janela(hoje))
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
                continue  # dia ainda aberto: nao entra na conta da semana
            try:
                quando = datetime.fromtimestamp(int(p["time"]), timezone.utc).date()
            except (KeyError, ValueError, OSError):
                continue
            valores = p.get("value") or []
            for i, termo in enumerate(termos):
                if i < len(valores) and valores[i] is not None:
                    por_termo[termo].append((quando, float(valores[i])))

        # GUARDA DE GRANULARIDADE. A janela de 240 dias vem em dias hoje, mas
        # quem decide isso e o Google, e o limiar e dele. Se ele passar a
        # devolver semanal, `semanas_iso` acharia um ponto por balde, exigiria
        # sete e devolveria serie vazia -- silencio, que e como o erro de seis
        # dias sobreviveu tanto tempo. Melhor estourar dizendo o que mudou.
        amostra = sorted(next((d for d in por_termo.values() if len(d) > 1), []))
        if amostra:
            passo = (amostra[1][0] - amostra[0][0]).days
            if passo != 1:
                raise TrendsErro(
                    "Trends devolveu passo de {} dia(s), e nao diario, para a "
                    "janela de {} dias. A perna de busca depende do dia para "
                    "montar a semana ISO; reveja DIAS_DA_JANELA.".format(
                        passo, DIAS_DA_JANELA))
        return dict((t, semanas_iso(dias)) for t, dias in por_termo.items())


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
        return sorted(aprovados, key=lambda t: t["id"]), "semanal"

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
        # `granularidade` fica registrado porque muda o que o numero E: a
        # semana aqui e media de sete dias medidos, e nao o ponto semanal que
        # o Trends entrega pronto. Regra 3: o caminho ate a origem tem que
        # dizer tambem COMO o ponto foi montado.
        meta = {"fonte": "google_trends", "geo": GEO, "intervalo": janela(hoje),
                "granularidade": "diaria->semana_iso",
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

    # UMA ESCALA POR SERIE.
    #
    # O upsert cobre as 34 semanas da janela e deixa intactas as anteriores,
    # que vieram do `today 5-y`. O Trends normaliza 0-100 DENTRO de cada
    # consulta, entao as duas partes nao estao na mesma regua e a emenda vira
    # um degrau. Medido na primeira execucao, em `alfaiataria`:
    #
    #   2025-12-01  14.00  antigo      2025-12-15   3.71  novo
    #   2025-12-08   6.00  novo        2025-12-29   0.00  novo
    #
    # A janela movel de 12 semanas da §21 atravessaria essa costura e leria o
    # degrau como movimento -- "em queda" sobre uma troca de unidade, que a
    # regra 2 proibe. O tamanho depende do volume do termo: `vestido` passa com
    # +2%, `alfaiataria` com -70%, `algodao` com -95%.
    #
    # Reescalar foi medido e descartado: o fator erra 2,4% em `alfaiataria` e
    # 20,8% (max 60%) em `vestido floral` -- a ancora do K7, regua de todos os
    # outros. O maior erro cairia no ponto de maior consequencia.
    #
    # As linhas antigas ja foram para `series_busca_5y_legado` na migracao
    # 20260805180000; aqui a limpeza continua acontecendo a cada rotacao, senao
    # os proximos 12 termos recriam a costura.
    for termo_id, dados in dados_por_termo.items():
        if not dados["pontos"]:
            continue
        primeira = min(s for s, _ in dados["pontos"]).isoformat()
        supabase_rest.apagar(
            "series_semanais",
            "termo_id=eq.{}&fonte=eq.busca&semana=lt.{}".format(
                termo_id, primeira))
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
    hoje = date.today()

    # Em dia = cobre a ultima semana ISO que ja fechou. A regua vem da FONTE,
    # e nao do relogio.
    #
    # O corte antigo era `hoje - 2 semanas`, escolhido a mao para compensar o
    # atraso do Trends. Com o deslocamento de seis dias em cima (veja
    # `semanas_iso`), a ultima semana gravada aparecia como 20/07 enquanto o
    # corte pedia 22/07 -- todo termo parecia atrasado todos os dias, e o
    # coletor gastava execucao inteira reconsultando quem ja estava em dia.
    # Com a semana montada a partir do dia, a comparacao fecha exata.
    #
    # A cobertura vem da view `cobertura_da_busca`, uma linha por termo. Fazer
    # isso no cliente NAO funciona: o PostgREST corta em 1000 linhas por
    # resposta e `selecionar()` nao pagina, entao puxar `series_semanais`
    # inteira fez o coletor concluir "36 termos sem serie" quando eram QUATRO.
    corte = ultima_semana_fechada(hoje).isoformat()
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

    t = Trends()
    t.aquecer()
    agora = datetime.now(timezone.utc).isoformat()

    id_da_ancora = next((x["id"] for x in aprovados
                         if x["termo_busca"] == ANCORA), None)
    falhas = []
    ancora_pontos = None
    total_pontos = 0
    mortos = []
    termos_com_serie = set()

    for i, grupo in enumerate(grupos, 1):
        consulta = [ANCORA] + [x["termo_busca"] for x in grupo]
        try:
            series = t.serie(consulta, hoje)
        except TrendsErro as e:
            falhas.append({"grupo": i, "erro": str(e)})
            print("  grupo {}/{}: FALHOU ({})".format(i, len(grupos), e),
                  file=sys.stderr)
            continue

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
    tentados = len(grupos)
    responderam = tentados - len(falhas)
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
        "alertas": {
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
        },
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
    # Codigo de saida diferente de zero quando NENHUM grupo passou: assim o
    # Actions marca a execucao como falha em vez de verde silencioso.
    if tentados and not responderam:
        print("ERRO: nenhum grupo respondeu. A perna de busca nao avancou hoje.",
              file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
