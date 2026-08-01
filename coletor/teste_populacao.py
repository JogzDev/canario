"""Teste do filtro de populacao do motor de atributos (§11, §17, B4).

Este arquivo existe por causa de tres erros que o projeto ja cometeu, todos da
MESMA familia: **texto que nao descreve a peca entrando como se descrevesse.**

  1. 30/07 -- a descricao de marketing. 74% dos casamentos de `reta_wide` vinham
     dela, com "caimento amplo" virando silhueta de perna.
  2. 30/07 -- o `content:encoded` do editorial, que trouxe o rodape do site
     junto e levou a taxa de casamento a 84%.
  3. 01/08 -- o nome da marca. `/dress to/Bazar/Blusas/` fazia toda a Dress To
     virar `vestido`, porque `dress` esta em `vestido.palavras_en`.

O terceiro so apareceu porque fui checar de onde vinham os similares. Nenhum
dos tres aparece como erro: os tres aparecem como um numero maior e melhor.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from matcher import compilar_lista, termos_que_casam  # noqa: E402
from motor_atributos import (e_acessorio, fora_do_segmento,  # noqa: E402
                             limpar_nome_da_marca)

falhas = []


def checa(descricao, obtido, esperado):
    if obtido != esperado:
        falhas.append("{}\n   esperado: {!r}\n   obtido:   {!r}".format(
            descricao, esperado, obtido))


# ---------------------------------------------------------------------------
# O nome da marca nao descreve o produto
# ---------------------------------------------------------------------------

# Vocabulario real dos dois termos que colidiam.
TERMOS = {
    "vestido": compilar_lista(["vestido", "vestidinho", "dress"]),
    "vermelho_rosa": compilar_lista(["vermelho", "rosa", "pink", "cereja", "vinho"]),
    "blusa_top": compilar_lista(["blusa", "top", "cropped", "regata"]),
}


def casa(texto, marca):
    return termos_que_casam(limpar_nome_da_marca(texto, marca), TERMOS)


# O caso que custou 6.895 ligacoes erradas.
checa("blusa da Dress To nao e vestido",
      casa("Blusa Canelada Gola Alta /dress to/Bazar/Blusas/", "Dress To"),
      {"blusa_top"})
checa("bolsa da Dress To nao e vestido",
      casa("Bolsa Palha Franjas /dress to/Shop/Acessorios/", "Dress To"),
      set())

# E o que NAO pode ser perdido junto: vestido de verdade continua vestido.
checa("vestido da Dress To continua vestido",
      casa("Vestido Cropped Linho Fenda /dress to/Shop/Vestidos/", "Dress To"),
      {"vestido", "blusa_top"})   # cropped tambem casa blusa_top, e esta certo

# O caso da cor: 612 ligacoes erradas.
checa("regata da Morena Rosa nao e rosa",
      casa("Regata Morena Rosa Solta Decote Quadrado Off White", "Morena Rosa"),
      {"blusa_top"})
checa("peca rosa da Morena Rosa continua rosa",
      casa("Regata Morena Rosa Solta Decote Quadrado Rosa", "Morena Rosa"),
      {"blusa_top", "vermelho_rosa"})

# A limpeza e por palavra inteira: nao pode comer pedaco de outra palavra.
checa("marca curta nao come palavra vizinha",
      limpar_nome_da_marca("Vestido NV Envelope", "NV").split(),
      ["vestido", "envelope"])
checa("marca sem colisao nao muda nada",
      limpar_nome_da_marca("Vestido Floral Midi", "Farm"),
      "vestido floral midi")
checa("marca ausente do texto nao muda nada",
      limpar_nome_da_marca("Calca Alfaiataria", "Le Lis Blanc"),
      "calca alfaiataria")

# ---------------------------------------------------------------------------
# Acessorio e calcado nao sao peca de roupa
# ---------------------------------------------------------------------------

# Verdadeiros: o titulo comeca pelo tipo.
for titulo in ["Bolsa Tiracolo Couro", "Sandalia Salto Bloco", "Brinco Argola",
               "Colar Solaris E Luna", "Bota Cano Curto", "Oculos De Sol Gatinho",
               "Necessaire Pequena", "Carteira Ziriguidum", "Luva Meiota"]:
    checa("acessorio: {}".format(titulo), e_acessorio(titulo, None), True)

# FALSOS que a medicao encontrou. Estes sao roupa, e a regra tem de deixar passar.
#
# `cinto` aparece em 1.117 titulos e so 127 sao cintos; `lenco` em 207 e so 49.
# Uma regra que valesse em qualquer posicao jogaria fora quase mil pecas.
for titulo in ["Vestido Midi Com Cinto", "Macacao Xadrez Com Cinto",
               "Calca Lenco Crepe Estampa", "Saia Lenco Estampada",
               "Blusa Meia Manga Canelada", "Camisa Com Botoes",
               "Saia Carteira Linho", "Vestido Com Corrente Metalica"]:
    checa("roupa, nao acessorio: {}".format(titulo), e_acessorio(titulo, None), False)

# A segunda porta: categoria do site nomeia o acessorio.
checa("categoria delata o acessorio",
      e_acessorio("Gargantilha Metal Com Citrino", "/Loja/Acessorios/"), True)
checa("categoria estruturada, palavra em qualquer posicao",
      e_acessorio("Maxi Necessaire", "/Feminino/Brincos/"), True)

# ---------------------------------------------------------------------------
# O filtro de populacao que ja existia continua valendo
# ---------------------------------------------------------------------------

checa("masculino fora", fora_do_segmento("camisa masculina slim"), True)
checa("infantil fora", fora_do_segmento("vestido infantil floral"), True)
checa("moda praia fora", fora_do_segmento("biquini cortininha"), True)
checa("lingerie fora", fora_do_segmento("calcinha algodao"), True)
checa("roupa feminina fica", fora_do_segmento("vestido midi floral"), False)

# A regressao de sempre, agora cruzando este caminho.
checa("`bota` nao pode casar `botao`", e_acessorio("Camisa Com Botao", None), False)
checa("`meia` nao pode casar `meia manga`",
      e_acessorio("Blusa Meia Manga", None), False)


if falhas:
    print("\n\n".join(falhas))
    print("\n{} falhas".format(len(falhas)))
    sys.exit(1)

print("Filtro de populacao: todos os casos passaram.")
print("Principio: o que nao descreve a peca nao vira atributo da peca.")
