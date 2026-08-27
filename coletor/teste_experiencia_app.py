"""Guardrails dos defeitos de UX encontrados nos testes físicos de 21/08 e 25/08."""

import math
import re
from pathlib import Path


RAIZ = Path(__file__).resolve().parents[1]
APP = RAIZ / "app" / "Canario"
MANEQUIM = (APP / "Assets.xcassets" / "AddMannequin.imageset"
            / "AddMannequin.svg")


def ler(relativo):
    return (APP / relativo).read_text(encoding="utf-8")


def centro_do_botao_add():
    """Onde o `+` cai dentro do quadro, em unidades do viewBox.

    O JP reclamou duas vezes do mesmo botão. Na primeira, o `+` estava em
    x=77 num desenho cujo eixo é x=50 -- 27 unidades fora. Corrigido com um
    `translate`, ele foi para 50,001 e ainda parecia torto, porque o quadro
    ('0 0 108 232') tem centro em 54: `scaledToFit` centraliza o QUADRO, não a
    tinta, então o desenho inteiro nascia 4 unidades à esquerda.

    Comparar texto não pega isso. Este teste compara os dois números.
    """
    svg = MANEQUIM.read_text(encoding="utf-8")
    vb = re.search(r'viewBox="(-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+)"', svg)
    assert vb, "AddMannequin.svg sem viewBox legível"
    vb_x, _, vb_w, _ = (float(v) for v in vb.groups())

    grupo = re.search(
        r'<g transform="translate\((-?[\d.]+) (-?[\d.]+)\)">(.*?)</g>',
        svg, re.S)
    assert grupo, "o `+` precisa continuar num <g> com translate próprio"
    dx = float(grupo.group(1))

    circulo = re.search(r'<circle cx="([\d.]+)"[^>]*r="([\d.]+)"', grupo.group(3))
    assert circulo, "círculo do botão + não encontrado dentro do <g>"
    return float(circulo.group(1)) + dx, vb_x + vb_w / 2


def main():
    componentes = ler("Design/Componentes.swift")
    termo = ler("Telas/RelatorioDoTermo.swift")
    peca = ler("Telas/RelatorioDaPeca.swift")
    importar = ler("Telas/ImportarPeca.swift")

    assert 'Label("Not confirmed"' not in componentes
    assert '.presentationCompactAdaptation(.popover)' not in componentes
    assert '.presentationCompactAdaptation(.sheet)' in componentes
    assert '.presentationDetents([.height(360)])' in componentes
    assert '.presentationDetents([.medium])' not in componentes
    assert 'ScrollView {' in componentes

    for relatorio in (termo, peca):
        assert 'Text("Limits")' not in relatorio
        assert "Insufficient coverage:" not in relatorio
    assert 'titulo: "Not enough items yet"' not in termo
    assert 'titulo: "No combined reading for this item yet"' not in peca
    assert 'Text(Leitura.emPalavras(valor))' not in peca

    assert '.focused($dicaDoAlvoEmFoco)' in importar
    assert 'Button("Done") { dicaDoAlvoEmFoco = false }' in importar
    assert '.scrollDismissesKeyboard(.interactively)' in importar
    assert 'guard !termos.isEmpty else {' in importar
    assert 'no visual-analysis credit was used' in importar
    assert '.accessibilityLabel("Photo options")' in importar
    assert 'private func voltarUmaEtapa()' in importar
    assert 'precoOpcional' in importar

    # O visual novo da BranchFadul manteve o calculo do teto diario e apagou a
    # linha que o mostrava, e apagou a frase de privacidade inteira. As duas
    # voltaram; estes portoes existem para elas nao sairem de novo sem que
    # alguem note.
    assert 'if let avisoDeUso {' in importar
    assert 'LinhaInsumo(texto: avisoDeUso)' in importar
    assert 'The app prepares the image on this iPhone and asks before sending' in importar
    assert 'The app reads the file on this iPhone.' in importar
    # Build de colaborador (REMOTE_ANALYSIS_ENABLED = NO) precisa dizer que a
    # analise esta desligada, em vez de parecer que ela falhou.
    assert 'Cloud visual analysis is off in this build' in importar

    # O card do manequim já é centralizado na tela pela VStack; o que sobrava
    # era o desenho estar torto DENTRO do card. Meia unidade de tolerância é
    # menos de 0,5 pt no tamanho renderizado -- abaixo do que o olho separa,
    # e apertado o bastante para reprovar os 4 e os 27 de antes.
    botao, centro = centro_do_botao_add()
    assert math.isclose(botao, centro, abs_tol=0.5), (
        "o + do Add está em x={:.3f} e o centro do quadro em x={:.3f}: "
        "{:.3f} unidades fora".format(botao, centro, abs(botao - centro)))

    print("UX físico: ausência silenciosa, ajuda adaptativa, teclado com saída "
          "e o + do Add a {:.3f} unidade do centro".format(abs(botao - centro)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
