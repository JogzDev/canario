"""Regressões do portão operacional de saúde."""

import os
import sys
from datetime import date, datetime, timedelta, timezone

from gerar_saude import data_operacional
from coletor_editorial import data_operacional as data_operacional_editorial
from coletor_varejo import (alertas_criticos, cobertura_da_marca,
                            frase_de_cobertura, metricas_varejo_ativas,
                            resumo_de_cobertura)


HOJE = date(2026, 8, 2)
MARCAS = [{"id": 1, "nome": "Marca A"}]


def linha(fonte, valor, dias=0, marca_id=None):
    return {
        "id": dias + 1,
        "data": (HOJE - timedelta(days=dias)).isoformat(),
        "fonte": fonte,
        "marca_id": marca_id,
        "visitados": valor if fonte == "varejo" else 1,
        "gravados": valor,
        "itens": None if fonte == "varejo" else valor,
        "criado_em": "2026-08-02T10:00:00Z",
    }


def main():
    depois_da_meia_noite_utc = datetime(
        2026, 8, 5, 1, 27, tzinfo=timezone.utc)
    if data_operacional(depois_da_meia_noite_utc) != date(2026, 8, 4):
        print("FALHOU: portao trocou de dia antes de Sao Paulo")
        return 1

    anterior = os.environ.get("DATA_OPERACIONAL")
    try:
        os.environ["DATA_OPERACIONAL"] = "2026-08-03"
        if data_operacional(depois_da_meia_noite_utc) != date(2026, 8, 3):
            print("FALHOU: recuperacao ignorou a data operacional fixada")
            return 1
        if data_operacional_editorial(depois_da_meia_noite_utc) != date(2026, 8, 3):
            print("FALHOU: editorial ignorou a data operacional fixada")
            return 1
        os.environ["DATA_OPERACIONAL"] = "03-08-2026"
        try:
            data_operacional(depois_da_meia_noite_utc)
        except ValueError:
            pass
        else:
            print("FALHOU: data operacional invalida nao falhou fechada")
            return 1
    finally:
        if anterior is None:
            os.environ.pop("DATA_OPERACIONAL", None)
        else:
            os.environ["DATA_OPERACIONAL"] = anterior

    saudavel = [linha("varejo", 100, marca_id=1),
                linha("editorial", 80), linha("busca", 40)]
    if alertas_criticos(saudavel, MARCAS, HOJE)[0]:
        print("FALHOU: fontes saudaveis foram bloqueadas")
        return 1

    sem_busca = [linha("varejo", 100, marca_id=1), linha("editorial", 80)]
    if not any("busca sem observacao" in x
               for x in alertas_criticos(sem_busca, MARCAS, HOJE)[0]):
        print("FALHOU: ausencia de busca nao bloqueou")
        return 1

    busca_em_dia = linha("busca", 0)
    busca_em_dia["visitados"] = 0
    busca_em_dia["alertas"] = {
        "adiado_por_cadencia": True,
        "motivo": "todas as series de busca estao em dia",
    }
    cadencia = [linha("varejo", 100, marca_id=1), linha("editorial", 80),
                busca_em_dia]
    crit, avisos = alertas_criticos(cadencia, MARCAS, HOJE)
    if crit or not any("já estavam em dia" in x for x in avisos):
        print("FALHOU: skip semanal do Trends foi tratado como pane")
        return 1

    animale_adiada = linha("varejo", 0, marca_id=1)
    animale_adiada["visitados"] = 0
    animale_adiada["alertas"] = {
        "adiado_por_capacidade": True,
        "motivo": "fallback publico aguarda folga operacional",
    }
    por_capacidade = [animale_adiada, linha("editorial", 80),
                      linha("busca", 40)]
    crit, avisos = alertas_criticos(por_capacidade, MARCAS, HOJE)
    if crit or not any("folga operacional" in x for x in avisos):
        print("FALHOU: adiamento explicito por capacidade virou pane")
        return 1
    estado, detalhe = cobertura_da_marca(animale_adiada["alertas"])
    if (estado != "incerta"
            or detalhe.get("adiado_por_capacidade") is not True):
        print("FALHOU: adiamento por capacidade declarou catalogo completo")
        return 1

    animale_semanal = linha("varejo", 0, marca_id=1)
    animale_semanal["visitados"] = 0
    animale_semanal["alertas"] = {
        "adiado_por_cadencia": True,
        "cadencia": "semanal",
        "proxima_coleta_em": "2026-08-03",
        "motivo": "varredura integral ocorre às segundas-feiras",
    }
    por_cadencia = [animale_semanal, linha("editorial", 80),
                    linha("busca", 40)]
    crit, avisos = alertas_criticos(por_cadencia, MARCAS, HOJE)
    if crit or not any("segundas-feiras" in x for x in avisos):
        print("FALHOU: cadencia semanal explicita virou pane")
        return 1
    estado, detalhe = cobertura_da_marca(animale_semanal["alertas"])
    if (estado != "incerta"
            or detalhe.get("adiado_por_cadencia") is not True):
        print("FALHOU: dia sem varredura declarou catalogo completo")
        return 1

    queda = [linha("varejo", 20, marca_id=1),
             linha("editorial", 80), linha("busca", 40)]
    queda.extend(linha("varejo", 100, dias=d, marca_id=1)
                 for d in range(1, 8))
    if not any("caiu 80%" in x
               for x in alertas_criticos(queda, MARCAS, HOJE)[0]):
        print("FALHOU: queda maior que 70% nao bloqueou")
        return 1

    # TROCAR A JANELA DO TRENDS NAO E COLETA QUEBRADA.
    #
    # Em 06/08 o portao barrou o pipeline com "busca caiu 87% (462 vs 3626)".
    # A coleta tinha funcionado: os mesmos grupos responderam. O que mudou foi
    # a janela -- de 5 anos semanais (261 pontos por termo) para 240 dias
    # diarios (34). `itens` conta ponto, e ponto e unidade de janela.
    janela_menor = [linha("varejo", 100, marca_id=1), linha("editorial", 80)]
    hoje_busca = linha("busca", 3)
    hoje_busca["itens"] = 462          # um oitavo do de ontem
    janela_menor.append(hoje_busca)
    for d in range(1, 8):
        antiga = linha("busca", 3, dias=d)
        antiga["itens"] = 3626         # janela de 5 anos
        janela_menor.append(antiga)
    if any("busca" in x for x in alertas_criticos(janela_menor, MARCAS, HOJE)[0]):
        print("FALHOU: troca de janela do Trends bloqueou como se fosse queda")
        return 1

    # Mas cobertura caindo de verdade continua bloqueando.
    cobertura_caiu = [linha("varejo", 100, marca_id=1), linha("editorial", 80),
                      linha("busca", 1)]
    cobertura_caiu.extend(linha("busca", 8, dias=d) for d in range(1, 8))
    if not any("busca caiu" in x
               for x in alertas_criticos(cobertura_caiu, MARCAS, HOJE)[0]):
        print("FALHOU: queda real de cobertura da busca nao bloqueou")
        return 1

    # LOJA QUE RECUSOU HOJE NAO E COLETA QUEBRADA.
    #
    # Em 09 e 10/08 o pipeline caiu por "varejo/Amaro retornou zero", e o motivo
    # gravado era `http 429 (persistiu apos backoff longo)` -- a loja pedindo
    # para diminuir, que a regra 7 manda respeitar. Medido em 9 dias: Amaro 8
    # bons e 2 zerados, PatBo 8 bons e 2 zerados E recuperou sozinha.
    def zerada(dias, erro="http 429"):
        l = linha("varejo", 0, dias=dias, marca_id=1)
        l["visitados"] = 0
        l["alertas"] = {"erro": erro}
        return l

    um_dia = [zerada(0), linha("editorial", 80), linha("busca", 40)]
    um_dia.extend(linha("varejo", 100, dias=d, marca_id=1) for d in range(1, 8))
    crit, avisos = alertas_criticos(um_dia, MARCAS, HOJE)
    if any("Marca A" in x for x in crit):
        print("FALHOU: um dia de recusa da loja travou o pipeline")
        return 1
    if not any("Marca A" in x for x in avisos):
        print("FALHOU: a recusa sumiu em vez de virar aviso")
        return 1

    # Motivo qualquer nao basta. Só uma recusa externa conhecida pode usar a
    # tolerância; parse, contrato ou exceção interna continuam bloqueando.
    erro_interno = [zerada(0, erro="json inesperado"),
                    linha("editorial", 80), linha("busca", 40)]
    erro_interno.extend(
        linha("varejo", 100, dias=d, marca_id=1) for d in range(1, 8))
    crit, _ = alertas_criticos(erro_interno, MARCAS, HOJE)
    if not any("erro interno/desconhecido" in x for x in crit):
        print("FALHOU: erro interno foi tolerado como recusa da fonte")
        return 1

    # Respeitar robots.txt é uma recusa explícita da origem, não pane do
    # coletor. No primeiro dia preserva a última observação e avisa; três dias
    # seguidos continuam bloqueando como fonte que deixou de ser observável.
    robots = [zerada(0, erro="robots proibe a busca"),
              linha("editorial", 80), linha("busca", 40)]
    robots.extend(
        linha("varejo", 100, dias=d, marca_id=1) for d in range(1, 8))
    crit, avisos = alertas_criticos(robots, MARCAS, HOJE)
    if any("Marca A" in x for x in crit) or not any(
            "robots proibe" in x for x in avisos):
        print("FALHOU: recusa por robots nao seguiu a tolerancia curta")
        return 1

    # Tres dias seguidos ja nao e um dia ruim.
    tres_dias = [zerada(0), zerada(1), zerada(2),
                 linha("editorial", 80), linha("busca", 40)]
    tres_dias.extend(linha("varejo", 100, dias=d, marca_id=1) for d in range(3, 8))
    crit, _ = alertas_criticos(tres_dias, MARCAS, HOJE)
    if not any("3 dias seguidos" in x for x in crit):
        print("FALHOU: zero persistente nao bloqueou")
        return 1

    # Zero SEM motivo e pior que zero com motivo: nao sabemos o que houve.
    sem_motivo = [zerada(0, erro=None), linha("editorial", 80), linha("busca", 40)]
    sem_motivo.extend(linha("varejo", 100, dias=d, marca_id=1) for d in range(1, 8))
    crit, _ = alertas_criticos(sem_motivo, MARCAS, HOJE)
    if not any("sem dizer por qu" in x for x in crit):
        print("FALHOU: zero inexplicado nao bloqueou")
        return 1

    metricas = metricas_varejo_ativas(
        {("varejo", 1): linha("varejo", 100, marca_id=1),
         ("varejo", 2): linha("varejo", 0, marca_id=2)},
        {1: ("Marca A", "vtex"), 2: ("Marca inativa", "vtex")}, MARCAS)
    if len(metricas) != 1 or metricas[0]["marca_id"] != 1:
        print("FALHOU: relatorio incluiu observacao de marca fora do escopo ativo")
        return 1

    # COBERTURA -- o caso real da C&A em 18/08/2026. Volume normal, nenhuma
    # queda, portao verde, e quatro faixas truncadas em 2.500 na mesma pagina.
    # O relatorio dizia so "sem alerta critico". Este teste existe para que
    # verde nunca mais signifique "catalogo inteiro" sem alguem ter conferido.
    cea = {
        "erro": "http 500 ao contar categoria VTEX 1000003/1004161/1004167",
        "truncou": "faixa de preco indivisivel acima de 2500",
        "faixas_truncadas": [
            {"faixa": "0-1", "existem": 41053, "coletados": 2500},
            {"faixa": "0-1", "existem": 11280, "coletados": 2500},
            {"faixa": "0-1", "existem": 7215, "coletados": 2500},
            {"faixa": "0-1", "existem": 6875, "coletados": 2500},
        ],
    }
    estado, detalhe = cobertura_da_marca(cea)
    if estado != "parcial" or detalhe["faixas"] != 4:
        print("FALHOU: faixa truncada nao virou cobertura parcial")
        return 1
    # 38553 + 8780 + 4715 + 4375 = 56.423 produtos, no teto
    if detalhe["teto_de_perda"] != 56423 or detalhe["pior_faixa"] != 38553:
        print("FALHOU: teto de perda calculado errado ({})".format(detalhe))
        return 1

    # Erro de contagem sem faixa truncada nao e "completa": e desconhecido.
    estado, _ = cobertura_da_marca(
        {"erro": "catalogo VTEX declarou zero na categoria 28"})
    if estado != "incerta":
        print("FALHOU: falha de contagem foi tratada como catalogo inteiro")
        return 1

    for vazio in (None, {}, {"divergencia": {"coletado": 1, "paginavel": 2}}):
        if cobertura_da_marca(vazio)[0] != "completa":
            print("FALHOU: marca sem corte foi acusada de cobertura parcial")
            return 1

    contagem, por_marca = resumo_de_cobertura([
        {"nome": "C&A", "alertas": cea},
        {"nome": "Hering", "alertas": None},
        {"nome": "Dress To", "alertas": {"erro": "categoria 28 zerada"}},
    ])
    if contagem != {"completa": 1, "parcial": 1, "incerta": 1}:
        print("FALHOU: resumo de cobertura contou errado ({})".format(contagem))
        return 1
    if len(por_marca) != 3:
        print("FALHOU: resumo perdeu marca")
        return 1

    # A frase e o que aparece ao lado de "sem alerta critico". Se ela nao
    # mudar quando ha corte, o relatorio volta a enganar quem le rapido.
    frase = frase_de_cobertura(contagem)
    if "parcial" not in frase or "2 de 3" not in frase:
        print("FALHOU: linha de estado escondeu o corte de catalogo ({})".format(
            frase))
        return 1
    if "completa" not in frase_de_cobertura(
            {"completa": 15, "parcial": 0, "incerta": 0}):
        print("FALHOU: dia integro nao foi reconhecido como completo")
        return 1

    print("Saude: fuso BRT, ausencia, zero, queda >70% e cobertura do catalogo")
    return 0


if __name__ == "__main__":
    sys.exit(main())
