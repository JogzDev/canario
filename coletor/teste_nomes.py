"""Varredura de nome usado e nunca definido, em stdlib pura.

POR QUE ESTE ARQUIVO EXISTE
===========================

Em 05/08 o coletor de busca morreu no runner com:

    NameError: name 'ja_tem' is not defined

Ao reescrever a fila por defasagem eu removi a variavel `ja_tem` e deixei um
uso orfao dela 250 linhas abaixo, no calculo da linha de saude. O coletor fez
todo o trabalho certo -- 1.827 pontos gravados, a fila com os 40 termos -- e
morreu na ultima etapa, montando o relatorio.

E o que doi: eu VALIDEI o arquivo antes de subir, com `ast.parse`. Passou
limpo. `ast.parse` confere SINTAXE; nome indefinido e erro de EXECUCAO, e so
aparece quando a linha roda. Como aquela linha so roda depois de meia hora
conversando com o Google, ela nao roda em teste nenhum.

`pyflakes` resolveria isso em um comando, e a maquina nao tem. Entao a
verificacao vem para dentro do projeto, em stdlib, e roda junto com as outras
suites -- porque este e o tipo de erro que reaparece em toda refatoracao e nao
pode depender de eu lembrar.

O QUE ELE CONFERE
=================

Para cada funcao, junta tudo que cria nome ali dentro (parametros, atribuicao,
`for`, `with...as`, `except...as`, comprehensions, `import`, def aninhado,
`global`/`nonlocal`) mais o escopo do modulo, mais os builtins. O que sobra
usado e nao definido e reportado.

Conservador de proposito: na duvida, cala. Um teste que acusa o que esta certo
ensina a ignorar o teste, que e como um teste morre.

Rodar: python3 coletor/teste_nomes.py
"""

import ast
import builtins
import os
import sys

RAIZ = os.path.dirname(os.path.abspath(__file__))
EMBUTIDOS = set(dir(builtins)) | {"__file__", "__name__", "__doc__"}


def _alvos(no):
    """Nomes criados por um alvo de atribuicao (a, (a, b), [a, b], a.b, a[0])."""
    if isinstance(no, ast.Name):
        return {no.id}
    if isinstance(no, (ast.Tuple, ast.List)):
        return set().union(*[_alvos(e) for e in no.elts]) if no.elts else set()
    if isinstance(no, ast.Starred):
        return _alvos(no.value)
    # a.b = ... e a[0] = ... nao criam nome novo.
    return set()


class Escopo(ast.NodeVisitor):
    """Junta os nomes que um corpo de funcao cria."""

    def __init__(self):
        self.criados = set()

    def visit_Name(self, no):
        if isinstance(no.ctx, (ast.Store, ast.Del)):
            self.criados.add(no.id)
        self.generic_visit(no)

    def visit_arg(self, no):
        self.criados.add(no.arg)

    def visit_alias(self, no):
        self.criados.add((no.asname or no.name).split(".")[0])

    def visit_ExceptHandler(self, no):
        if no.name:
            self.criados.add(no.name)
        self.generic_visit(no)

    def visit_Global(self, no):
        self.criados.update(no.names)

    def visit_Nonlocal(self, no):
        self.criados.update(no.names)

    def _def(self, no):
        self.criados.add(no.name)
        # Nao desce: o corpo da funcao aninhada tem escopo proprio, conferido
        # separadamente. Descer aqui daria falso NEGATIVO, nao positivo.

    visit_FunctionDef = _def
    visit_AsyncFunctionDef = _def
    visit_ClassDef = _def


def _do_corpo(no):
    """Nomes criados dentro de um def, sem entrar nos defs aninhados."""
    e = Escopo()
    for arg in no.args.args + no.args.kwonlyargs + no.args.posonlyargs:
        e.criados.add(arg.arg)
    if no.args.vararg:
        e.criados.add(no.args.vararg.arg)
    if no.args.kwarg:
        e.criados.add(no.args.kwarg.arg)
    for filho in no.body:
        e.visit(filho)
    return e.criados


def _usados(no):
    """Nomes lidos dentro de um def, sem entrar nos defs aninhados."""
    lidos = []

    class Leitor(ast.NodeVisitor):
        def visit_Name(self, n):
            if isinstance(n.ctx, ast.Load):
                lidos.append((n.id, n.lineno))
            self.generic_visit(n)

        def _pula(self, n):
            pass

        visit_FunctionDef = _pula
        visit_AsyncFunctionDef = _pula
        visit_ClassDef = _pula

    for filho in no.body:
        Leitor().visit(filho)
    return lidos


def conferir(caminho):
    arvore = ast.parse(open(caminho, encoding="utf-8").read(), caminho)

    # Escopo do modulo: tudo criado no nivel de cima, em qualquer profundidade
    # de bloco (if/try/for de modulo tambem criam nome global).
    do_modulo = Escopo()
    for no in arvore.body:
        do_modulo.visit(no)

    achados = []

    # A TRAVESSIA E ESTRUTURAL, E NAO `ast.walk`.
    #
    # A primeira versao usava `ast.walk`, que achata a arvore inteira: funcao
    # aninhada era conferida contra o escopo do MODULO, e nao contra o da
    # funcao que a contem. Resultado: 22 falsos positivos, todos closure
    # legitima (`lidos`, `achados`, `falhas`...). Um teste que acusa o que
    # esta certo ensina a ignorar o teste.
    def visitar(no, escopo):
        if isinstance(no, (ast.FunctionDef, ast.AsyncFunctionDef)):
            # O proprio nome entra: funcao recursiva se enxerga.
            dentro = escopo | _do_corpo(no) | {no.name}
            for nome, linha in _usados(no):
                if nome not in dentro:
                    achados.append((linha, nome, no.name))
            for filho in no.body:
                visitar(filho, dentro)
            return
        if isinstance(no, ast.ClassDef):
            # Metodo nao enxerga o corpo da classe, mas enxerga a funcao que a
            # contem. Passar `escopo` adiante e o comportamento certo.
            for filho in no.body:
                visitar(filho, escopo)
            return
        # if/try/for/while nao criam escopo: desce mantendo o mesmo.
        for filho in ast.iter_child_nodes(no):
            visitar(filho, escopo)

    for no in arvore.body:
        visitar(no, do_modulo.criados | EMBUTIDOS)

    # Um mesmo nome pode aparecer por varios caminhos de aninhamento.
    return sorted(set(achados))


def _autoteste():
    """Prova que o verificador MORDE, antes de confiar num resultado limpo.

    Um verificador que nao acha nada pode estar certo ou pode estar quebrado, e
    de fora as duas coisas sao identicas. O primeiro caso abaixo e o bug real de
    05/08, reduzido: variavel criada num trecho, removida na refatoracao, e um
    uso orfao sobrevivendo mais abaixo na mesma funcao.
    """
    import tempfile

    casos = [
        # (codigo, quantos indefinidos esperados, o que esta sendo provado)
        ("def main():\n"
         "    em_dia = set()\n"
         "    cobertura = len(ja_tem | em_dia)\n"
         "    return cobertura\n", 1, "pega o uso orfao (o bug de 05/08)"),

        # Closure: `lidos` vem de fora. NAO pode acusar.
        ("def fora():\n"
         "    lidos = []\n"
         "    def dentro():\n"
         "        lidos.append(1)\n"
         "    dentro()\n", 0, "nao acusa closure legitima"),

        # Recursao: a funcao se enxerga. NAO pode acusar.
        ("def particao(n):\n"
         "    if n <= 0:\n"
         "        return []\n"
         "    return particao(n - 1)\n", 0, "nao acusa recursao"),

        # Nome do modulo visto de dentro da funcao. NAO pode acusar.
        ("ANCORA = 'vestido floral'\n"
         "def usar():\n"
         "    return ANCORA\n", 0, "nao acusa constante de modulo"),
    ]

    problemas = []
    for codigo, esperado, oque in casos:
        with tempfile.NamedTemporaryFile("w", suffix=".py", delete=False,
                                         encoding="utf-8") as f:
            f.write(codigo)
            caminho = f.name
        try:
            achou = len(conferir(caminho))
        finally:
            os.unlink(caminho)
        marca = "ok  " if achou == esperado else "FALHOU"
        print("  {} autoteste: {} (esperado {}, achou {})".format(
            marca, oque, esperado, achou))
        if achou != esperado:
            problemas.append(oque)
    return problemas


def main():
    print("Nome usado e nunca definido\n")
    problemas = _autoteste()
    if problemas:
        print("\nO VERIFICADOR ESTA QUEBRADO; o resultado abaixo nao vale.")
        return 1
    print()
    total = falhas = 0
    for nome in sorted(os.listdir(RAIZ)):
        if not nome.endswith(".py"):
            continue
        caminho = os.path.join(RAIZ, nome)
        total += 1
        for linha, indefinido, funcao in conferir(caminho):
            falhas += 1
            print("  {}:{}  {!r} usado em {}() e nunca definido".format(
                nome, linha, indefinido, funcao))

    print("\n{} arquivos varridos, {} nome(s) indefinido(s).".format(total, falhas))
    if not falhas:
        print("`ast.parse` confere sintaxe; isto confere se o nome existe.")
    return 1 if falhas else 0


if __name__ == "__main__":
    sys.exit(main())
