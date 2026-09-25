"""Guardrails dos fluxos de leitura, navegação e prova da edição 2.0."""

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
    semana = ler("Telas/EstaSemana.swift")
    dados_semana = ler("Rede/DadosDaSemana.swift")
    opcoes = ler("Telas/OpcoesDaConta.swift")
    raiz = ler("CanarioApp.swift")

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

    # As superfícies substitutas continuam ligadas à navegação, sem os
    # destinos legados que pintavam outro tema por cima da edição.
    assert 'EstaSemana(abrirConta:' in raiz
    assert 'MinhasPecas(abrirConta:' in raiz
    assert 'Estudio(abrirConta:' in raiz
    assert 'TelaDoMenu(entrada:' in raiz
    assert 'MenuLateral(' not in raiz
    assert '.territorio(.armario)' not in opcoes
    assert '.papelDaEdicao()' in opcoes
    assert 'Folha {' in opcoes
    assert 'CabecalhoDaFolha(titulo: Text(titulo))' in opcoes
    assert 'BotaoDoMenu' not in componentes

    # A capa usa a agregação da janela inteira, e o número por marca continua
    # sendo de produtos distintos, não de exemplos ou eventos brutos.
    assert '"resumo_de_eventos"' in dados_semana
    assert '"eventos_recentes"' not in dados_semana
    assert 'historia.marca.pecas' in semana
    assert 'marca.pecas' in semana

    # A57/A58: o app consome as funcoes NOVAS, e as antigas ficam no banco
    # servindo os aparelhos que ninguem atualizou. Se a tela voltasse a chamar
    # a versao sem sufixo, a v2 existiria sem consumidor e a correcao de
    # frescor nao chegaria a tela nenhuma.
    peca = ler("Telas/RelatorioDaPeca.swift")
    assert '"similares_da_peca_amplo_v2"' in peca, (
        "a tela da peca precisa chamar o envelope v2")
    assert '"similares_da_peca_amplo"' not in peca.replace(
        '"similares_da_peca_amplo_v2"', ""), (
        "sobrou chamada ao envelope antigo na tela da peca")

    print("Experiência 2.0: leitura, navegação, privacidade e contagem da capa conferidas")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
