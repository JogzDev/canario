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
INTERVALO = "today 5-y"
ANCORA = "vestido floral"   # K7: fixa em todos os grupos
POR_GRUPO = 5               # teto do Trends
TZ = 180                    # minutos; BRT = UTC-3

ESPERA_ENTRE = 12.0         # o Trends bloqueia rapido; generoso de proposito
ESPERAS_429 = [30, 90, 240]

# Abaixo disto a serie e considerada sem sinal utilizavel (C3). Media do valor
# bruto na janela inteira: o Trends normaliza 0-100, entao media < 1 significa
# que o termo praticamente nao aparece.
MEDIA_MINIMA = 1.0


class TrendsErro(Exception):
    pass


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

    def token_timeseries(self, termos):
        req = {"comparisonItem": [{"keyword": t, "geo": GEO, "time": INTERVALO}
                                  for t in termos],
               "category": 0, "property": ""}
        url = (BASE + "/trends/api/explore?hl=pt-BR&tz={}&req={}".format(
            TZ, urllib.parse.quote(json.dumps(req, separators=(",", ":")))))
        d = self._json(self._get(url, BASE + "/trends/explore"))
        for w in d.get("widgets", []):
            if w.get("id") == "TIMESERIES":
                return w.get("token"), w.get("request")
        raise TrendsErro("explore nao devolveu widget TIMESERIES")

    def serie(self, termos):
        """Devolve {termo: [(semana_date, valor), ...]} para o grupo."""
        token, requisicao = self.token_timeseries(termos)
        url = (BASE + "/trends/api/widgetdata/multiline"
               "?hl=pt-BR&tz={}&req={}&token={}".format(
                   TZ,
                   urllib.parse.quote(json.dumps(requisicao, separators=(",", ":"))),
                   urllib.parse.quote(token)))
        d = self._json(self._get(url, BASE + "/trends/explore"))
        pontos = (d.get("default") or {}).get("timelineData") or []
        saida = dict((t, []) for t in termos)
        for p in pontos:
            if p.get("isPartial"):
                continue  # semana incompleta: nao entra na serie
            try:
                quando = datetime.fromtimestamp(int(p["time"]), timezone.utc).date()
            except (KeyError, ValueError, OSError):
                continue
            semana = quando - timedelta(days=quando.weekday())  # segunda ISO
            valores = p.get("value") or []
            for i, termo in enumerate(termos):
                if i < len(valores) and valores[i] is not None:
                    saida[termo].append((semana, float(valores[i])))
        return saida


def grupos_de_termos(termos_aprovados):
    """K7: ancora fixa + 4 novos por grupo."""
    fila = [t for t in termos_aprovados if t["termo_busca"] != ANCORA]
    tamanho = POR_GRUPO - 1
    return [fila[i:i + tamanho] for i in range(0, len(fila), tamanho)]


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
        meta = {"fonte": "google_trends", "geo": GEO, "intervalo": INTERVALO,
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
    if atualizacoes:
        supabase_rest.upsert("termos", atualizacoes, on_conflict="id")
    return len(linhas), [a for a in atualizacoes if a["sem_perna_busca"] == "sim"]


def main():
    if not supabase_rest.configurado():
        print("ERRO: SUPABASE_URL/SUPABASE_SECRET_KEY ausentes.", file=sys.stderr)
        return 1

    # regra 4: so termo aprovado, e so com termo_busca preenchido.
    aprovados = [t for t in supabase_rest.selecionar(
        "termos", "?status=eq.aprovado&select=id,termo_busca,dimensao&order=id")
        if (t.get("termo_busca") or "").strip()]
    if not aprovados:
        print("Nenhum termo aprovado com termo_busca. Nada a coletar.", file=sys.stderr)
        return 0

    grupos = grupos_de_termos(aprovados)
    print("Termos aprovados: {} | grupos de {}: {} | ancora fixa: {!r}".format(
        len(aprovados), POR_GRUPO, len(grupos), ANCORA), file=sys.stderr)

    t = Trends()
    t.aquecer()
    hoje = date.today()
    agora = datetime.now(timezone.utc).isoformat()

    id_da_ancora = next((x["id"] for x in aprovados
                         if x["termo_busca"] == ANCORA), None)
    falhas = []
    ancora_pontos = None
    total_pontos = 0
    mortos = []

    for i, grupo in enumerate(grupos, 1):
        consulta = [ANCORA] + [x["termo_busca"] for x in grupo]
        try:
            series = t.serie(consulta)
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

    # A propria ancora e um termo da taxonomia (`floral`): a serie dela tambem
    # precisa ser gravada, senao o termo mais usado do sistema fica sem perna.
    if id_da_ancora and ancora_pontos:
        gravados, _ = gravar_grupo(
            {id_da_ancora: {"termo_busca": ANCORA, "pontos": ancora_pontos,
                            "grupo": 0, "media_ancora": None}}, hoje, agora)
        total_pontos += gravados
        print("  ancora {!r}: {} pontos gravados".format(ANCORA, gravados),
              file=sys.stderr)

    print("\nTotal: {} pontos de serie.".format(total_pontos), file=sys.stderr)
    print("Sem perna de busca ({}): {}".format(
        len(mortos), ", ".join(sorted(mortos)) or "nenhum"), file=sys.stderr)
    if falhas:
        print("Grupos que falharam: {}".format(falhas), file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
