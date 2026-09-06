#!/usr/bin/env python3
"""Fixture sintetica do P1: uma etiqueta, um conceito, uma revisao.

POR QUE ISTO EXISTE
===================

O `executar.mjs` sobe um PostgreSQL descartavel, aplica a A51 e o
`schema_admissao.sql`, e entrega aos testes um objeto JSON em
`current_setting('lab.fixture')`. Este script produz esse objeto.

Ele nao e um gerador de dados de exemplo: e a UNICA entrada da passagem
completa que o P1 precisa demonstrar (coleta -> extracao -> evidencia draft ->
leitura draft -> recibo). Cada campo aqui existe porque a
`lab_radar.admitir_etiqueta_v1` o exige, e a funcao rejeita o manifesto inteiro
quando um deles falta, sobra ou nao casa com o registro de fontes.

TUDO AQUI E SINTETICO, E ISSO E VERIFICAVEL
===========================================

`synthetic: true` viaja no manifesto e a funcao de admissao recusa qualquer
manifesto sem essa marca. Os tres textos de tela comecam com "FICTÍCIO —" por
exigencia do proprio schema, que e a regra inviolavel 2 escrita em `check`
constraint: dado ficticio precisa estar marcado como ficticio NA INTERFACE, nao
so num arquivo a parte.

O revisor sintetico se chama `SIMULADO_*`. Simulacao nao e julgamento humano
independente, e o nome existe para nenhum relatorio futuro poder confundir os
dois -- e o mesmo cuidado que a blueprint pede no item 6 do checklist do P1.

O QUE ESTE SCRIPT NAO PROVA
===========================

Que o parser real da Etiqueta funciona, que a revisao cega dupla foi feita por
duas pessoas, ou que existe fonte externa admissivel. Ele prova que a fundacao
aceita exatamente uma passagem valida e rejeita as invalidas -- nada alem.

USO
===

    python3 gerar_fixture.py --destination-id <UUID>

Escreve um objeto JSON em stdout. Nao toca em rede, arquivo nem variavel de
ambiente: o `executar.mjs` executa este script num ambiente explicito, sem
nenhuma credencial.
"""
import argparse
import datetime
import hashlib
import json
import sys
import uuid

# A fonte interna semeada pela A51. Os tres hashes abaixo sao os que estao NO
# BANCO; a admissao compara campo a campo e recusa qualquer divergencia. Eles
# nao sao segredo: descrevem o registro publico de uma fonte de conteudo
# proprio, e mudam junto com a migration se ela mudar.
FONTE_INTERNA = "datadrobe_curadoria_interna"
REGISTRO_SHA256 = "2a135e1f7741ae200da89552b32664bf86df76ffb93a25486a2a2d7290894075"
CONTRATO_SHA256 = "1faf19de3b2ed6c844acee7711fd78b90db8b9f40206533ec24ad73c33e095ba"
AUTORIZACAO_SHA256 = "adc6fba462d0e10c53a08857cba8a4875c4c5d7b77a84875e9e2cb5ab6d9db49"

# O conceito da passagem. Fibra, porque a Etiqueta e o primeiro sensor e
# composicao declarada e o unico fato que ela sustenta sem inferencia.
CONCEITO_ID = "algodao_declarado_lab"
PROTOCOLO = "protocolo_sintetico_lab_p1_v1"

# Versoes de metodo. Sao rotulos de contrato, nao numeros de release do app:
# mudar qualquer um deles muda a identidade logica da evidencia, que e
# exatamente o comportamento que o teste de reprocessamento exercita.
MATERIALIZADOR = "datadrobe_label_fact_pack_v2"
EXTRACAO = "etiqueta_parser_v1"
METODOLOGIA = "metodologia_lab_p1_v1"
TEMPLATE = "template_lab_p1_v1"

SEMENTE = "datadrobe/lab-radar/p1/fixture/v1"


def hash_de(*partes):
    """SHA-256 determinístico de um rotulo.

    Deterministico de proposito: a mesma fixture, rodada duas vezes, produz a
    mesma identidade logica -- que e o que permite o teste de idempotencia
    comparar recibos entre execucoes em vez de so dentro de uma.
    """
    corpo = "|".join([SEMENTE] + [str(p) for p in partes])
    return hashlib.sha256(corpo.encode("utf-8")).hexdigest()


def segunda_feira(dia):
    """A segunda-feira da semana ISO de `dia`.

    O schema exige `extract(isodow from semana) = 1`. Nao e capricho: recorte
    semanal que comeca em dias diferentes nao e comparavel com ele mesmo.
    """
    return dia - datetime.timedelta(days=dia.isoweekday() - 1)


def montar(destination_id, agora=None):
    agora = agora or datetime.datetime.now(datetime.timezone.utc)
    # Duas horas atras: a admissao recusa observacao no futuro (mais de 10
    # minutos a frente) e a folga evita que a diferenca de relogio entre este
    # processo e o PostgreSQL derrube a suite por um segundo.
    observado = agora - datetime.timedelta(hours=2)
    dia_observado = observado.date()
    semana = segunda_feira(dia_observado)
    periodo_fim = dia_observado
    periodo_inicio = periodo_fim - datetime.timedelta(days=6)

    fato_id = hash_de("fato", CONCEITO_ID, "algodao", "corpo")
    manifesto = {
        "contract": "datadrobe_label_admission_manifest_v1",
        "manifest_id": hash_de("manifesto", destination_id),
        # Identidade LOGICA: nao inclui a tentativa nem o horario da execucao.
        # Reprocessar o mesmo conteudo devolve o recibo existente; mudar
        # conteudo sob a mesma identidade e conflito, nao sobrescrita.
        "logical_key": hash_de("identidade_logica", FONTE_INTERNA, fato_id,
                               CONCEITO_ID, 1, EXTRACAO, METODOLOGIA, TEMPLATE),
        "destination_id": destination_id,
        "source_package_id": hash_de("pacote_materializado"),
        "reviewed_package_id": hash_de("pacote_revisado"),
        "review_batch_id": hash_de("lote_de_revisao"),
        # Dois revisores cegos e distintos. A funcao recusa hashes iguais: duas
        # submissoes identicas seriam a mesma leitura contada duas vezes.
        "review_submission_sha256": [hash_de("revisao", "alias_a"),
                                     hash_de("revisao", "alias_b")],
        # Consenso entre os dois: nao houve adjudicacao. `null` e o valor certo
        # aqui, e nao um hash inventado para preencher o campo.
        "adjudication_submission_sha256": None,
        "concept_review_sha256": hash_de("revisao_conceitual", CONCEITO_ID),
        "fact_id": fato_id,
        "review_subject_id": hash_de("assinatura_semantica", EXTRACAO,
                                     "fiber", "composicao", "algodao"),
        "source_id": FONTE_INTERNA,
        "source_registry_sha256": REGISTRO_SHA256,
        "source_contract_sha256": CONTRATO_SHA256,
        "authorization_sha256": AUTORIZACAO_SHA256,
        "code_sha": hash_de("codigo")[:40],
        "materializer_version": MATERIALIZADOR,
        "extraction_version": EXTRACAO,
        "methodology_version": METODOLOGIA,
        "template_version": TEMPLATE,
        "concept_id": CONCEITO_ID,
        "concept_version": 1,
        "concept_contract_sha256": hash_de("contrato_do_conceito", CONCEITO_ID),
        "source_item_external_id": "lab:etiqueta-sintetica:0001",
        "content_sha256": hash_de("conteudo_da_etiqueta"),
        "observed_at": observado.isoformat(),
        "period_start": periodo_inicio.isoformat(),
        "period_end": periodo_fim.isoformat(),
        "geo": "BR",
        "language": "pt",
        "unit": "declared_composition_percentage",
        # Percentual de UMA parte declarada da peca. Nao e share de mercado, e
        # dois materiais na mesma peca sao duas incidencias -- por isso a parte
        # viaja junto do numero em vez de o numero viajar sozinho.
        "value": {"percentage": 92.0, "part_id": "tecido_principal"},
        "summary": "FICTÍCIO — etiqueta sintética declara 92% de algodão no "
                   "tecido principal de uma peça de laboratório.",
        "title": "FICTÍCIO — composição declarada em peça de laboratório",
        "reading_summary": "FICTÍCIO — uma única observação sintética, sem "
                           "cobertura para afirmar movimento de mercado.",
        # As lacunas nao sao enfeite: e a leitura declarando o que NAO sabe,
        # que e a razao de o estagio nascer `insufficient`.
        "gaps": [
            "Uma única peça observada: sem painel, sem denominador e sem série.",
            "Sensor único (etiqueta interna); nenhuma fonte externa admitida.",
            "Sem comparação temporal: não existe semana anterior neste corpus.",
            "Revisão simulada pelo laboratório, não julgamento humano independente.",
        ],
        "week": semana.isoformat(),
        "locale": "pt-BR",
        "synthetic": True,
    }

    # O dossie do conceito.
    #
    # `volume_observado` sai do TAMANHO de `supporting_subject_ids`, e nao de um
    # numero digitado ao lado da lista. O schema exige `volume_observado >=
    # volume_minimo_exigido` para aprovar um conceito; se o numero fosse
    # independente da lista, dava para "aprovar" um conceito digitando um
    # volume que nenhuma evidencia sustenta -- que e a fraude mais barata
    # possivel contra a regra inviolavel 2, e ela seria feita por engano.
    dossie = {
        "id": CONCEITO_ID,
        "family": "fiber",
        "label_pt": "Algodão declarado (laboratório)",
        "definition": "Fibra de algodão declarada na etiqueta de composição de "
                      "uma peça, com percentual e parte da peça explícitos. "
                      "Não inclui aparência têxtil nem inferência por imagem.",
        "aliases": ["algodão", "algodao", "cotton"],
        "positive_examples": ["92% algodão / 8% elastano — tecido principal",
                              "100% algodão — corpo"],
        "negative_examples": ["Aspecto acetinado (aparência, não fibra)",
                              "Cetim (construção têxtil, não fibra)"],
        "promotion_protocol_version": PROTOCOLO,
        "supporting_subject_ids": [hash_de("sujeito", n) for n in range(3)],
        "minimum_evidence_count": 3,
    }

    revisao = {
        "status": "approved",
        # SIMULADO, e o nome diz. Simulacao nao vira "aprovacao do JP" em
        # relatorio nenhum: o protocolo de producao sera congelado antes de
        # avaliar candidatos reais, e este aqui e exclusivamente sintetico.
        "reviewer": "SIMULADO_CONCEITO",
        "protocol": PROTOCOLO,
        "synthetic": True,
    }

    return {"manifest": manifesto, "concept_dossier": dossie,
            "concept_review": revisao}


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--destination-id", required=True,
                   help="UUID do destino criado por executar.mjs nesta invocação")
    args = p.parse_args()
    try:
        destino = str(uuid.UUID(args.destination_id))
    except ValueError:
        sys.stderr.write("destination-id precisa ser um UUID\n")
        return 2
    json.dump(montar(destino), sys.stdout, ensure_ascii=False)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
