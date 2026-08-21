"""Guardrails dos quatro defeitos de UX encontrados no teste físico de 21/08."""

from pathlib import Path


RAIZ = Path(__file__).resolve().parents[1]
APP = RAIZ / "app" / "Canario"


def ler(relativo):
    return (APP / relativo).read_text(encoding="utf-8")


def main():
    componentes = ler("Design/Componentes.swift")
    termo = ler("Telas/RelatorioDoTermo.swift")
    peca = ler("Telas/RelatorioDaPeca.swift")
    importar = ler("Telas/ImportarPeca.swift")

    assert 'Label("Not confirmed"' not in componentes
    assert '.presentationCompactAdaptation(.popover)' not in componentes
    assert '.presentationCompactAdaptation(.sheet)' in componentes
    assert 'ScrollView {' in componentes

    for relatorio in (termo, peca):
        assert 'Text("Limits")' not in relatorio
        assert "Insufficient coverage:" not in relatorio
    assert 'titulo: "Not enough items yet"' not in termo
    assert 'titulo: "No combined reading for this item yet"' not in peca

    assert '.focused($dicaDoAlvoEmFoco)' in importar
    assert 'Button("Done") { dicaDoAlvoEmFoco = false }' in importar
    assert '.scrollDismissesKeyboard(.interactively)' in importar

    print("UX físico: ausência silenciosa, ajuda adaptativa e teclado com saída")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
