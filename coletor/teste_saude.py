"""Regressões do portão operacional de saúde."""

import sys
from datetime import date, datetime, timedelta, timezone

from gerar_saude import data_operacional
from coletor_varejo import alertas_criticos, metricas_varejo_ativas


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

    # Motivo qualquer nao basta. So uma recusa HTTP conhecida pode usar a
    # tolerancia; parse, contrato ou excecao interna continuam bloqueando.
    erro_interno = [zerada(0, erro="json inesperado"),
                    linha("editorial", 80), linha("busca", 40)]
    erro_interno.extend(
        linha("varejo", 100, dias=d, marca_id=1) for d in range(1, 8))
    crit, _ = alertas_criticos(erro_interno, MARCAS, HOJE)
    if not any("erro nao HTTP" in x for x in crit):
        print("FALHOU: erro interno foi tolerado como recusa da fonte")
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

    print("Saude: fuso BRT, ausencia, zero e queda >70% bloqueiam")
    return 0


if __name__ == "__main__":
    sys.exit(main())
