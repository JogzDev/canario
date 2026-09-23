#!/usr/bin/env python3
"""Contrato offline da sonda gerenciada, sem rede nem escrita externa."""

import datetime as dt
import json
from pathlib import Path
import socket
import sys
import tempfile
import unittest
import urllib.error


RAIZ = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))

import sondar_origem_gerenciada as sonda


ROBOTS_LIBERADO = b"User-agent: CanarioBot\nAllow: /\n"
CORPOS_VALIDOS = {
    "vtex": b'[{"productId":"1","items":[]}]',
    "shopify": b'{"products":[{"id":1}]}',
    "wp_json": b'[{"id":1,"link":"https://example/post","title":{"rendered":"x"}}]',
    "xml": b'<rss><channel><item><title>x</title></item></channel></rss>',
    "sitemap": (b'<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">'
                b'<url><loc>https://loja.example/produtos/x/</loc></url></urlset>'),
}


class RelogioFalso:
    def __init__(self):
        self.agora = 0.0
        self.esperas = []

    def monotonic(self):
        return self.agora

    def sleep(self, segundos):
        self.esperas.append(segundos)
        self.agora += segundos


class RespostaFalsa:
    def __init__(self, status, corpo=b""):
        self.status = status
        self.corpo = corpo
        self.leituras = []

    def getcode(self):
        return self.status

    def read(self, limite=-1):
        self.leituras.append(limite)
        return self.corpo if limite < 0 else self.corpo[:limite]

    def __enter__(self):
        return self

    def __exit__(self, tipo, valor, traceback):
        return False


class OpenerFalso:
    def __init__(self, respostas):
        self.respostas = dict(respostas)
        self.requisicoes = []

    def open(self, requisicao, timeout):
        url = requisicao.full_url
        self.requisicoes.append({
            "url": url,
            "metodo": requisicao.get_method(),
            "user_agent": requisicao.get_header("User-agent"),
            "accept_encoding": requisicao.get_header("Accept-encoding"),
            "timeout": timeout,
        })
        resposta = self.respostas[url]
        if isinstance(resposta, BaseException):
            raise resposta
        return resposta


def alvo(identificador, url, validacao="vtex"):
    return {
        "id": identificador,
        "classe": "fixture",
        "url": url,
        "validacao": validacao,
    }


def url_robots(url):
    return "https://{}/robots.txt".format(url.split("/")[2])


def executar(alvos, respostas, relogio=None):
    relogio = relogio or RelogioFalso()
    opener = OpenerFalso(respostas)
    resultado = sonda.sondar(
        alvos=alvos,
        opener=opener,
        clock=relogio.monotonic,
        sleep=relogio.sleep,
        agora=lambda: dt.datetime(2026, 9, 16, tzinfo=dt.timezone.utc),
    )
    return resultado, opener, relogio


def corpo_explore(token="token-secreto", pedido=None):
    pedido = pedido or {"time": "today 3-m", "resolution": "DAY"}
    dados = {"widgets": [{
        "id": "TIMESERIES", "token": token, "request": pedido,
    }]}
    return b")]}'\n" + json.dumps(dados).encode("utf-8")


def corpo_multiline(pontos=True):
    dados = {"default": {"timelineData": (
        [{"time": "1", "value": [42]}] if pontos else [])}}
    return b")]}'\n" + json.dumps(dados).encode("utf-8")


class SondaGerenciadaTests(unittest.TestCase):
    def test_allowlist_e_schema_sao_fechados(self):
        self.assertEqual(
            [(a["id"], a["classe"], a["url"], a["validacao"])
             for a in sonda.ALVOS],
            [
                ("vtex_cantao", "catalogo_vtex",
                 "https://www.cantao.com.br/api/catalog_system/pub/products/search/vestido?_from=0&_to=0",
                 "vtex"),
                ("shopify_patbo", "catalogo_shopify",
                 "https://www.patbo.com.br/products.json?limit=1", "shopify"),
                ("nuvemshop_amaro", "catalogo_nuvemshop",
                 "https://amaro.com/sitemap.xml", "sitemap"),
                ("editorial_ffw", "feed_editorial_wp_json",
                 "https://ffw.com.br/wp-json/wp/v2/posts?per_page=1&_fields=id,link,date,title",
                 "wp_json"),
                ("editorial_bof", "feed_editorial_rss",
                 "https://www.businessoffashion.com/arc/outboundfeeds/rss/?outputType=xml",
                 "xml"),
                ("google_trends", "busca_trends",
                 "https://trends.google.com/trends/?geo=BR", "trends"),
            ])
        self.assertEqual(len({a["id"] for a in sonda.ALVOS}), len(sonda.ALVOS))
        with self.assertRaises(ValueError):
            sonda.sondar(alvos=[alvo("x", "http://example.com", "vtex")])
        with self.assertRaises(ValueError):
            sonda.sondar(alvos=[alvo("x", "https://example.com", "desconhecida")])
        duplicado = alvo("x", "https://example.com", "vtex")
        with self.assertRaises(ValueError):
            sonda.sondar(alvos=[duplicado, dict(duplicado)])

    def test_quatro_formatos_validos_passam_com_leitura_limitada(self):
        for tipo, corpo in CORPOS_VALIDOS.items():
            with self.subTest(tipo=tipo):
                item = alvo(tipo, "https://{}.example/dado".format(tipo), tipo)
                robots = RespostaFalsa(200, ROBOTS_LIBERADO)
                endpoint = RespostaFalsa(200, corpo)
                resultado, opener, _ = executar([item], {
                    url_robots(item["url"]): robots,
                    item["url"]: endpoint,
                })
                self.assertEqual(len(opener.requisicoes), 2)
                self.assertTrue(all(r["metodo"] == "GET" for r in opener.requisicoes))
                self.assertTrue(all(r["user_agent"] == sonda.UA
                                    for r in opener.requisicoes))
                self.assertTrue(all(r["accept_encoding"] == "identity"
                                    for r in opener.requisicoes))
                self.assertEqual(robots.leituras, [sonda.MAX_BYTES_ROBOTS + 1])
                self.assertEqual(endpoint.leituras, [sonda.MAX_BYTES_ENDPOINT + 1])
                registro = resultado["alvos"][0]
                self.assertTrue(registro["endpoint"]["protocolo_valido"])
                self.assertEqual(resultado["veredito"], "apto_para_proxima_prova")

    def test_corpo_nunca_e_serializado(self):
        item = alvo("loja", "https://loja.example/catalogo", "vtex")
        segredo = b'segredo-que-nao-deve-ir-ao-artefato'
        corpo = b'[{"productId":"' + segredo + b'","items":[]}]'
        resultado, _, _ = executar([item], {
            url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
            item["url"]: RespostaFalsa(200, corpo),
        })
        serializado = json.dumps(resultado, ensure_ascii=False)
        self.assertNotIn(segredo.decode(), serializado)
        for proibido in ('"corpo":', '"headers":', '"cookies":', "Set-Cookie"):
            self.assertNotIn(proibido, serializado)
        self.assertTrue(resultado["nao_autoriza_migracao"])
        self.assertFalse(resultado["politica"]["supabase_consultado"])

    def test_200_incompativel_204_e_truncamento_nunca_passam(self):
        casos = [
            (200, b"<html>waf</html>", "resposta_incompativel"),
            (200, b"[]", "resposta_incompativel"),
            (200, b"\xff", "resposta_incompativel"),
            (204, b"", "http_204"),
            (200, b"x" * (sonda.MAX_BYTES_ENDPOINT + 1), "corpo_acima_do_limite"),
        ]
        for indice, (status, corpo, situacao) in enumerate(casos):
            with self.subTest(status=status, situacao=situacao):
                item = alvo("caso{}".format(indice),
                            "https://caso{}.example/dado".format(indice), "vtex")
                resultado, _, _ = executar([item], {
                    url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
                    item["url"]: RespostaFalsa(status, corpo),
                })
                endpoint = resultado["alvos"][0]["endpoint"]
                self.assertFalse(endpoint["protocolo_valido"])
                self.assertEqual(endpoint["situacao"], situacao)
                self.assertEqual(resultado["veredito"], "inconclusivo_ou_bloqueado")

    def test_206_so_e_valido_para_pagina_vtex_integra(self):
        for tipo, corpo, valido in (
            ("vtex", CORPOS_VALIDOS["vtex"], True),
            ("vtex", b"<html>waf</html>", False),
            ("vtex", b'[{"productId":"1","items":[]}', False),
            ("vtex", b"x" * (sonda.MAX_BYTES_ENDPOINT + 1), False),
            ("shopify", CORPOS_VALIDOS["shopify"], False),
        ):
            with self.subTest(tipo=tipo, valido=valido, tamanho=len(corpo)):
                item = alvo("loja", "https://loja.example/catalogo", tipo)
                resultado, _, _ = executar([item], {
                    url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
                    item["url"]: RespostaFalsa(206, corpo),
                })
                endpoint = resultado["alvos"][0]["endpoint"]
                self.assertEqual(endpoint["protocolo_valido"], valido)
                self.assertEqual(endpoint["http"], 206)

    def test_xml_com_doctype_ou_sem_item_falha_fechado(self):
        for indice, corpo in enumerate((
            b'<!DOCTYPE rss [<!ENTITY x "y">]><rss><channel><item/></channel></rss>',
            b'<rss><channel/></rss>',
        )):
            item = alvo("xml{}".format(indice),
                        "https://xml{}.example/feed".format(indice), "xml")
            resultado, _, _ = executar([item], {
                url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
                item["url"]: RespostaFalsa(200, corpo),
            })
            self.assertFalse(resultado["alvos"][0]["endpoint"]["protocolo_valido"])

    def test_robots_ausente_invalido_truncado_redirecionado_ou_negado_bloqueia(self):
        casos = {
            "ausente": RespostaFalsa(404),
            "invalido": RespostaFalsa(200, b"sem diretiva de agente"),
            "truncado": RespostaFalsa(
                200, b"User-agent: CanarioBot\nAllow: /\n" +
                b"x" * sonda.MAX_BYTES_ROBOTS),
            "negado": RespostaFalsa(200, b"User-agent: CanarioBot\nDisallow: /\n"),
            "redirecionado": urllib.error.HTTPError(
                "https://loja.example/robots.txt", 301, "Moved", {}, None),
        }
        for nome, resposta_robots in casos.items():
            with self.subTest(nome=nome):
                item = alvo(nome, "https://{}.example/catalogo".format(nome))
                resultado, opener, _ = executar([item], {
                    url_robots(item["url"]): resposta_robots,
                })
                self.assertEqual(len(opener.requisicoes), 1)
                endpoint = resultado["alvos"][0]["endpoint"]
                self.assertFalse(endpoint["executado"])
                self.assertFalse(endpoint["protocolo_valido"])

    def test_403_429_e_timeout_sao_diagnostico_e_nao_abortam_lote(self):
        primeiro = alvo("limitada", "https://limitada.example/catalogo")
        segundo = alvo("lenta", "https://lenta.example/catalogo")
        resultado, opener, _ = executar([primeiro, segundo], {
            url_robots(primeiro["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
            primeiro["url"]: RespostaFalsa(429),
            url_robots(segundo["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
            segundo["url"]: urllib.error.URLError(socket.timeout("fixture")),
        })
        self.assertEqual(len(opener.requisicoes), 4)
        self.assertEqual(
            [r["endpoint"]["situacao"] for r in resultado["alvos"]],
            ["http_429", "timeout"])
        self.assertEqual(resultado["resumo"]["endpoints_executados"], 2)
        self.assertEqual(resultado["resumo"]["protocolos_validos"], 0)

    def test_crawl_delay_e_request_rate_usam_o_maior_intervalo(self):
        casos = [
            (b"User-agent: CanarioBot\nAllow: /\nCrawl-delay: 3\n", 3.0),
            (b"User-agent: CanarioBot\nAllow: /\nCrawl-delay: 3.5\n", 3.5),
            (b"User-agent: CanarioBot\nAllow: /\nRequest-rate: 2/10\n", 5.0),
            (b"User-agent: CanarioBot\nAllow: /\nCrawl-delay: 3\nRequest-rate: 2/10\n",
             5.0),
        ]
        for indice, (robots_corpo, espera) in enumerate(casos):
            with self.subTest(espera=espera):
                item = alvo("cadencia{}".format(indice),
                            "https://cadencia{}.example/catalogo".format(indice))
                resultado, _, relogio = executar([item], {
                    url_robots(item["url"]): RespostaFalsa(200, robots_corpo),
                    item["url"]: RespostaFalsa(200, CORPOS_VALIDOS["vtex"]),
                })
                self.assertEqual(relogio.esperas, [espera])
                self.assertEqual(
                    resultado["alvos"][0]["robots"]["intervalo_minimo_segundos"],
                    espera)

    def test_robots_mais_especifico_curingas_grupos_e_escapes(self):
        casos = [
            ("User-agent: *\nAllow: /\nDisallow: /api/", "/api/catalogo", False),
            ("User-agent: *\nDisallow: /\nAllow: /api/", "/api/catalogo", True),
            ("User-agent: *\nDisallow: /*api/", "/v1/api/catalogo", False),
            ("User-agent: *\nDisallow: /api$", "/api", False),
            ("User-agent: *\nDisallow: /api$", "/api/catalogo", True),
            ("User-agent: *\nDisallow: /*?token=*", "/api?token=x", False),
            ("User-agent: *\nDisallow: /api\nAllow: /api", "/api", True),
            ("User-agent: CanarioBot\nAllow: /\n\nUser-agent: CanarioBot\n"
             "Disallow: /api/", "/api/catalogo", False),
            ("User-agent: OtherBot\nDisallow: /\nUser-agent: *\nAllow: /",
             "/api", True),
            ("User-agent: *\nDisallow: /\nUser-agent: canariobot\nAllow: /",
             "/api", True),
            ("User-agent: *\nDisallow: /caf%C3%A9", "/café", False),
            ("User-agent: *\nDisallow: /caf%C3%A9", "/caf%c3%a9", False),
            ("User-agent: *\nDisallow: /%61pi", "/api", False),
            ("User-agent: *\nDisallow: /a%2Fb", "/a/b", True),
            ("User-agent: *\nDisallow: /a%2Fb", "/a%2fb", False),
            ("User-agent: *\nDisallow: /a%2Ab", "/a*b", False),
            ("User-agent: *\nDisallow: /a%24b", "/a$b", False),
            ("User-agent : CanarioBot\nDisallow: /api", "/api", False),
        ]
        for regras, caminho, permitido in casos:
            with self.subTest(regras=regras, caminho=caminho):
                politica = sonda.PoliticaRobots(regras.splitlines())
                self.assertEqual(politica.can_fetch(
                    sonda.UA, "https://example.test" + caminho), permitido)

    def test_robots_merge_cadencia_usa_maior_valor_e_invalida_falha_fechada(self):
        politica = sonda.PoliticaRobots([
            "User-agent: CanarioBot", "Crawl-delay: 2", "Request-rate: 2/10",
            "User-agent: CanarioBot", "Crawl-delay: 4", "Request-rate: 1/8",
        ])
        self.assertEqual(politica.atraso, 4)
        self.assertEqual(politica.intervalo_taxa, 8)
        for diretiva in ("Crawl-delay: nan", "Crawl-delay: -1",
                         "Request-rate: 0/5", "Request-rate: nope",
                         "Disallow: api"):
            with self.subTest(diretiva=diretiva):
                item = alvo("loja", "https://loja.example/catalogo")
                resultado, opener, _ = executar([item], {
                    url_robots(item["url"]): RespostaFalsa(
                        200, ("User-agent: *\n" + diretiva).encode()),
                })
                self.assertEqual(len(opener.requisicoes), 1)
                self.assertFalse(resultado["alvos"][0]["endpoint"]["executado"])

    def test_erro_de_programacao_nao_vira_falha_de_rede(self):
        item = alvo("loja", "https://loja.example/catalogo")
        with self.assertRaises(KeyError):
            executar([item], {})

    def test_intervalo_robots_acima_do_teto_nao_e_burlado(self):
        item = alvo("lenta", "https://lenta.example/catalogo")
        resultado, opener, _ = executar([item], {
            url_robots(item["url"]): RespostaFalsa(
                200, b"User-agent: CanarioBot\nAllow: /\nRequest-rate: 1/16\n"),
        })
        self.assertEqual(len(opener.requisicoes), 1)
        registro = resultado["alvos"][0]
        self.assertEqual(registro["robots"]["request_rate_intervalo_segundos"], 16.0)
        self.assertEqual(registro["endpoint"]["motivo"],
                         "intervalo_robots_acima_do_limite_de_diagnostico")

    def test_trends_executa_warmup_explore_e_multiline_sem_expor_token(self):
        item = alvo("trends", "https://trends.google.com/trends/?geo=BR", "trends")
        token = "token-ultrassecreto"
        pedido = {"time": "today 3-m", "resolution": "DAY"}
        explore_url = sonda._url_explore_trends()
        multiline_url = sonda._url_multiline_trends(
            token, json.dumps(pedido, ensure_ascii=False, separators=(",", ":")))
        resultado, opener, relogio = executar([item], {
            url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
            item["url"]: RespostaFalsa(200, b"<html>ok</html>"),
            explore_url: RespostaFalsa(200, corpo_explore(token, pedido)),
            multiline_url: RespostaFalsa(200, corpo_multiline()),
        })
        self.assertEqual([r["url"] for r in opener.requisicoes], [
            url_robots(item["url"]), item["url"], explore_url, multiline_url,
        ])
        self.assertEqual(relogio.esperas, [1.0, 1.0, 1.0])
        endpoint = resultado["alvos"][0]["endpoint"]
        self.assertTrue(endpoint["protocolo_valido"])
        self.assertEqual([e["id"] for e in endpoint["etapas"]],
                         ["warmup", "explore", "multiline"])
        serializado = json.dumps(resultado)
        self.assertNotIn(token, serializado)
        self.assertNotIn("widgetdata", serializado)
        self.assertEqual(resultado["veredito"], "apto_para_proxima_prova")

    def test_trends_respeita_robots_em_cada_rota(self):
        item = alvo("trends", "https://trends.google.com/trends/?geo=BR", "trends")
        robots = b"User-agent: CanarioBot\nDisallow: /trends/api/\n"
        resultado, opener, _ = executar([item], {
            url_robots(item["url"]): RespostaFalsa(200, robots),
        })
        self.assertEqual(len(opener.requisicoes), 1)
        endpoint = resultado["alvos"][0]["endpoint"]
        self.assertFalse(endpoint["executado"])
        self.assertEqual(endpoint["situacao"], "robots_proibe_explore")

    def test_trends_widget_ausente_ou_timeline_vazia_falha_fechado(self):
        item = alvo("trends", "https://trends.google.com/trends/?geo=BR", "trends")
        explore_url = sonda._url_explore_trends()
        base = {
            url_robots(item["url"]): RespostaFalsa(200, ROBOTS_LIBERADO),
            item["url"]: RespostaFalsa(200, b"<html>ok</html>"),
        }
        resultado, _, _ = executar([item], {
            **base,
            explore_url: RespostaFalsa(200, b")]}'\n{\"widgets\":[]}"),
        })
        self.assertEqual(resultado["alvos"][0]["endpoint"]["situacao"],
                         "resposta_incompativel")

        token = "t"
        pedido = {"time": "today 3-m"}
        multiline_url = sonda._url_multiline_trends(
            token, json.dumps(pedido, separators=(",", ":")))
        resultado, _, _ = executar([item], {
            **base,
            explore_url: RespostaFalsa(200, corpo_explore(token, pedido)),
            multiline_url: RespostaFalsa(200, corpo_multiline(pontos=False)),
        })
        self.assertEqual(resultado["alvos"][0]["endpoint"]["situacao"],
                         "resposta_incompativel")

    def test_trends_exige_timestamp_e_um_valor_numerico_por_ponto(self):
        for ponto in (
            {"value": [42]}, {"time": "0", "value": [42]},
            {"time": "1", "value": []}, {"time": "1", "value": ["42"]},
            {"time": "1", "value": [True]}, {"time": "1", "value": [101]},
            {"time": "1", "value": [-1]}, {"time": "1", "value": [float("nan")]},
            {"time": "1", "value": [42, 43]},
        ):
            with self.subTest(ponto=ponto):
                corpo = json.dumps({"default": {"timelineData": [ponto]}}).encode()
                self.assertFalse(sonda._timeline_valida(corpo))
        for valor in (0, 42, 100):
            corpo = json.dumps({"default": {
                "timelineData": [{"time": "1", "value": [valor]}]}}).encode()
            self.assertTrue(sonda._timeline_valida(corpo))

    def test_conjunto_vazio_nunca_e_apto(self):
        resultado, opener, _ = executar([], {})
        self.assertEqual(opener.requisicoes, [])
        self.assertEqual(resultado["veredito"], "inconclusivo_ou_bloqueado")
        self.assertEqual(resultado["resumo"]["alvos"], 0)

    def test_saida_so_e_escrita_no_caminho_explicito(self):
        dados = {"schema": "fixture", "sem_corpo": True}
        with tempfile.TemporaryDirectory(prefix="sonda-gerenciada-") as pasta:
            destino = Path(pasta) / "resultado.json"
            sonda._escrever_json(str(destino), dados)
            self.assertEqual(json.loads(destino.read_text(encoding="utf-8")), dados)
            self.assertEqual({p.name for p in Path(pasta).iterdir()}, {"resultado.json"})
        with self.assertRaises(ValueError):
            sonda._escrever_json("/diretorio-inexistente/resultado.json", dados)


if __name__ == "__main__":
    unittest.main()
