"""Garante stage completo e publicação atômica fora do timeout HTTP."""

import sys

import motor_atributos
import motor_computar


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def testar_atributos():
    gravacoes = []
    rpcs = []

    motor_atributos.supabase_rest.configurado = lambda: True
    motor_atributos.carregar_termos = lambda: ({"vestido": object()},
                                                {"vestido"})
    motor_atributos.produtos_em_paginas = lambda: iter([[
        {"id": 1, "titulo": "Vestido reto", "descricao": None,
         "categoria_site": "Vestidos", "segmento": None, "marca_id": 10},
        {"id": 2, "titulo": "Bolsa media", "descricao": None,
         "categoria_site": "Acessorios", "segmento": "feminino_casual_br",
         "marca_id": 10},
    ]])
    motor_atributos.termos_que_casam = (
        lambda texto, termos: {"vestido"} if "vestido" in texto else set())
    motor_atributos.supabase_rest.selecionar = (
        lambda tabela, params="": [{"id": 10, "nome": "Marca X"}]
        if tabela == "marcas" else [])

    def upsert(tabela, linhas, on_conflict, retornar=False):
        gravacoes.append((tabela, [dict(x) for x in linhas], on_conflict))
        return []

    estados = iter([
        [{"status": "queued", "resultado": None, "erro": None}],
        [{"status": "success", "resultado": {
            "atributos": {"produtos": 2, "ligacoes": 1},
            "calculos": {nome: 1 for nome, _ in motor_computar.PASSOS}},
          "erro": None}],
    ])

    def rpc(metodo, caminho, corpo=None, **kwargs):
        rpcs.append((metodo, caminho, dict(corpo or {})))
        if caminho == "rpc/preparar_stage_motor":
            return 200, {"stage": "limpo", "execucoes_expiradas": 0}
        return 200, {"status": "queued"}

    motor_atributos.supabase_rest.upsert = upsert
    motor_atributos.supabase_rest._requisicao = rpc
    motor_atributos.supabase_rest.selecionar = (
        lambda tabela, params="": [{"id": 10, "nome": "Marca X"}]
        if tabela == "marcas" else next(estados))
    motor_atributos.time.sleep = lambda _: None
    motor_atributos.supabase_rest.apagar = (
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("nao pode apagar tabela viva pelo REST")))
    motor_atributos.supabase_rest.atualizar = (
        lambda *args, **kwargs: (_ for _ in ()).throw(
            AssertionError("nao pode atualizar segmento vivo pelo REST")))

    if motor_atributos.main() != 0:
        return falhar("motor_atributos retornou erro")

    tabelas = {g[0] for g in gravacoes}
    if tabelas != {"motor_produtos_stage", "motor_termos_stage"}:
        return falhar("matcher escreveu fora do stage: {}".format(tabelas))
    produtos = [x for tabela, linhas, _ in gravacoes
                if tabela == "motor_produtos_stage" for x in linhas]
    if len(produtos) != 2 or {x["segmento"] for x in produtos} != {
            None, "feminino_casual_br"}:
        return falhar("stage nao representa todos os produtos e segmentos")
    termos = [x for tabela, linhas, _ in gravacoes
              if tabela == "motor_termos_stage" for x in linhas]
    if len(termos) != 1 or termos[0]["termo_id"] != "vestido":
        return falhar("stage de termos incorreto")
    if [chamada[1] for chamada in rpcs] != [
            "rpc/preparar_stage_motor", "rpc/solicitar_publicacao_motor"]:
        return falhar("motor nao recupera stage antes de agendar a publicacao")
    if rpcs[1][2].get("p_total") != 2:
        return falhar("RPC nao recebeu a cardinalidade completa")
    return 0


def testar_computacao():
    chamadas = []
    motor_computar.supabase_rest.configurado = lambda: True

    def rpc(metodo, caminho, corpo=None, **kwargs):
        chamadas.append((metodo, caminho, corpo, kwargs))
        return 200, {nome: 1 for nome, _ in motor_computar.PASSOS}

    motor_computar.supabase_rest._requisicao = rpc
    if motor_computar.main() != 0:
        return falhar("motor_computar retornou erro")
    if len(chamadas) != 1 or chamadas[0][1] != "rpc/computar_motor":
        return falhar("calculo ainda chama RPCs separadas")
    if chamadas[0][3].get("tentativas") != 1:
        return falhar("lote atomico nao pode ter retry implicito")
    return 0


def testar_falha_observavel():
    motor_atributos.supabase_rest._requisicao = (
        lambda *args, **kwargs: (200, {"status": "queued"}))
    motor_atributos.supabase_rest.selecionar = (
        lambda *args, **kwargs: [{
            "status": "failed", "resultado": None,
            "erro": "57014: statement timeout",
        }])
    try:
        motor_atributos.publicar_e_aguardar("00000000-0000-0000-0000-000000000001", 2)
    except motor_atributos.supabase_rest.SupabaseErro as ex:
        if "57014: statement timeout" not in str(ex):
            return falhar("erro do worker perdeu o diagnostico SQL")
    else:
        return falhar("falha do worker foi tratada como sucesso")
    return 0


def main():
    return (testar_atributos() or testar_falha_observavel()
            or testar_computacao() or imprimir_sucesso())


def imprimir_sucesso():
    print("Motor: stage completo e job transacional unico, sem escrita viva parcial")
    return 0


if __name__ == "__main__":
    sys.exit(main())
