"""Regressoes do planejamento diario do Google Trends."""

import sys
from datetime import date, timedelta

from coletor_trends import (alertas_com_motivo_http, combinar_saude_busca,
                            corte_de_frescura, motivo_http_transitorio,
                            planejar_grupos, ultima_semana_fechada)


def main():
    grupos = [[str(i)] for i in range(9)]
    inicio = date(2026, 8, 3)
    vistos = set()
    for deslocamento in range(3):
        lote = planejar_grupos(grupos, inicio + timedelta(days=deslocamento))
        if len(lote) != 3:
            print("FALHOU: planejador excedeu o orcamento diario")
            return 1
        vistos.update(g[0] for g in lote)
    if vistos != set(str(i) for i in range(9)):
        print("FALHOU: tres lotes nao cobriram os nove grupos")
        return 1
    if planejar_grupos(grupos, inicio) != planejar_grupos(grupos, inicio):
        print("FALHOU: planejador nao e deterministico")
        return 1

    vistos_no_dia = set()
    for tentativa in range(3):
        lote = planejar_grupos(grupos, inicio, tentativa=tentativa)
        vistos_no_dia.update(g[0] for g in lote)
    if vistos_no_dia != set(str(i) for i in range(9)):
        print("FALHOU: recuperacoes do dia repetiram os mesmos grupos")
        return 1

    legado = {
        "visitados": 3, "gravados": 1, "itens": 1044,
        "alertas": {"grupos_que_falharam": [{"grupo": 1}]},
    }
    atual = {
        "visitados": 3, "gravados": 2, "itens": 1566,
        "alertas": {"modo": "backfill", "grupos_que_falharam": [
            {"grupo": 3}]},
    }
    combinada = combinar_saude_busca(legado, 1, atual)
    if (combinada["visitados"], combinada["gravados"], combinada["itens"]) != (
            6, 3, 2610):
        print("FALHOU: consolidacao nao preservou a primeira tentativa")
        return 1
    repetida = combinar_saude_busca(combinada, 1, atual)
    if repetida != combinada:
        print("FALHOU: repetir tentativa duplicou os totais")
        return 1

    recusas = [
        {"grupo": 1, "erro": "falhou apos 4 tentativas (HTTP 429)"},
        {"grupo": 2, "erro": "falhou apos 4 tentativas (HTTP 429)"},
    ]
    if motivo_http_transitorio(recusas) != (
            "http 429 em todos os 2 grupos apos backoff"):
        print("FALHOU: 429 conhecido nao virou causa de saude")
        return 1
    if motivo_http_transitorio(
            recusas + [{"grupo": 3, "erro": "JSON inesperado"}]) is not None:
        print("FALHOU: erro desconhecido foi mascarado como recusa HTTP")
        return 1
    antigos = {"grupos_que_falharam": recusas, "tentativa": 1}
    corrigidos = alertas_com_motivo_http(antigos)
    if corrigidos.get("erro") != "http 429 em todos os 2 grupos apos backoff":
        print("FALHOU: reconsolidacao nao recuperou causa da linha antiga")
        return 1
    if antigos.get("erro") is not None:
        print("FALHOU: reconsolidacao alterou o objeto de entrada")
        return 1

    # CORTE DE FRESCURA
    #
    # O caso que motivou o aperto, medido no aparelho do JP em 19/08/2026: o
    # app mostrava "week of 03/08" numa quarta-feira dia 19. A semana de 10/08
    # tinha fechado no domingo 16 e estava disponivel no Google -- uma coleta
    # forcada naquele mesmo dia a trouxe --, mas a regra tolerava ate quarta e
    # mandava pular.
    quarta = date(2026, 8, 19)
    if quarta.weekday() != 2:
        print("FALHOU: a data do caso real nao e mais quarta")
        return 1
    if ultima_semana_fechada(quarta) != date(2026, 8, 10):
        print("FALHOU: ultima semana fechada mudou de definicao")
        return 1
    if corte_de_frescura(quarta) != date(2026, 8, 10):
        print("FALHOU: quarta ainda tolera semana atrasada; o app volta a "
              "mostrar dado de 16 dias")
        return 1

    # Terca tambem exige. Segunda continua tolerante: a semana fechou na noite
    # de domingo e nao ha medicao de que o Google ja a tenha assentado.
    terca = date(2026, 8, 18)
    segunda = date(2026, 8, 17)
    if corte_de_frescura(terca) != ultima_semana_fechada(terca):
        print("FALHOU: terca deveria exigir a ultima semana fechada")
        return 1
    if corte_de_frescura(segunda) != ultima_semana_fechada(segunda) - timedelta(weeks=1):
        print("FALHOU: segunda deixou de tolerar o atraso de publicacao")
        return 1

    # De terca a domingo o corte e sempre a ultima semana fechada, sem excecao.
    for dia in range(18, 24):
        h = date(2026, 8, dia)
        if corte_de_frescura(h) != ultima_semana_fechada(h):
            print("FALHOU: {} ({}) nao exige a ultima semana fechada".format(
                h, h.strftime("%a")))
            return 1

    print("Trends: rotacao, saude idempotente e corte de frescura")
    return 0


if __name__ == "__main__":
    sys.exit(main())
