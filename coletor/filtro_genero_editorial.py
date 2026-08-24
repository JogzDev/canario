"""Classificação auditável do recorte editorial feminino.

Usa somente a manchete que já é persistida. Assim o histórico e a coleta nova
obedecem à mesma regra; resumo de feed não cria um regime melhor apenas daqui
para a frente. O viés declarado do veículo vale um sinal fraco e qualquer
sinal explícito no título pode vencê-lo.
"""

import re


PADROES_FEMININOS = (
    r"\bwom[ae]n(?:'s)?\b", r"\bwomenswear\b", r"\bfemale\b", r"\bgirls?\b",
    r"\bmulheres?\b", r"\bfeminin[oa]s?\b", r"\bgarotas?\b",
    r"\bbridal\b", r"\bbrides?\b", r"\bnoivas?\b", r"\bmaternity\b",
)
PADROES_MASCULINOS = (
    r"\bmen(?:'s)?\b", r"\bmenswear\b", r"\bman\b", r"\bmale\b", r"\bboys?\b",
    r"\bhomens?\b", r"\bmasculin[oa]s?\b", r"\brapazes?\b",
    r"\bgrooms?\b", r"\bnoivos?\b",
)


def _pontos(texto, padroes):
    return sum(1 for padrao in padroes if re.search(padrao, texto, re.I))


def classificar_genero(titulo, foco_do_veiculo="misto"):
    """Devolve público, placar e inclinação masculina em [0, 1].

    `masculino` significa estritamente mais de 50% dos sinais. Empate e título
    sem sinal permanecem no recorte, como o JP decidiu; escassez se resolve com
    mais fontes, não inventando gênero onde a manchete não o declarou.
    """
    texto = titulo or ""
    foco = (foco_do_veiculo or "misto").strip().lower()
    feminino = _pontos(texto, PADROES_FEMININOS) + (1 if foco == "feminino" else 0)
    masculino = _pontos(texto, PADROES_MASCULINOS) + (1 if foco == "masculino" else 0)
    total = feminino + masculino
    inclinacao = (masculino / float(total)) if total else 0.0
    if masculino > feminino:
        publico = "masculino"
    elif feminino > masculino:
        publico = "feminino"
    else:
        publico = "neutro"
    return {
        "publico": publico,
        "pontos_femininos": feminino,
        "pontos_masculinos": masculino,
        "inclinacao_masculina": round(inclinacao, 4),
    }
