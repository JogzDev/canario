"""Guarda invariantes do estado FINAL das migrations.

Migrations antigas contam a historia e podem conter definicoes revogadas. O
teste procura a ultima redefinicao de cada RPC para verificar o contrato que
um banco reconstruido termina servindo.
"""

import glob
import os
import re
import sys


RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PASTA = os.path.join(RAIZ, "supabase", "migrations")


def falhar(mensagem):
    print("FALHOU: {}".format(mensagem))
    return 1


def ultima_definicao(arquivos, assinatura):
    for caminho in reversed(arquivos):
        texto = open(caminho, encoding="utf-8").read()
        posicao = texto.lower().rfind(assinatura.lower())
        if posicao >= 0:
            return caminho, texto[posicao:]
    return None, ""


def main():
    arquivos = sorted(glob.glob(os.path.join(PASTA, "*.sql")))
    if not arquivos:
        return falhar("nenhuma migration encontrada")

    nomes_invalidos = [
        os.path.basename(c) for c in arquivos
        if not re.match(r"^\d{14}_[a-z0-9_]+\.sql$", os.path.basename(c))
    ]
    if nomes_invalidos:
        return falhar("migration fora do formato remoto: {}".format(
            ", ".join(nomes_invalidos)))

    _, cluster = ultima_definicao(
        arquivos, "create or replace function public.indice_do_cluster")
    exigencias_cluster = [
        "coalesce(c.suficiente, false)",
        "c.segmento = u.segmento",
        "i.segmento = 'feminino_casual_br'",
        "t.status = 'aprovado'",
    ]
    for trecho in exigencias_cluster:
        if trecho not in cluster:
            return falhar("cluster final nao garante: {}".format(trecho))

    _, similares = ultima_definicao(
        arquivos, "create or replace function public.similares_da_peca")
    exigencias_similares = [
        "t.status = 'aprovado'",
        "limit 12",
        "p.segmento = 'feminino_casual_br'",
        "least(greatest(coalesce($2, 12), 1), 24)",
        "p.ultimo_snapshot_em >= current_date - 14",
        "coalesce(g.esgotada, false) = false",
        "public.url_publica_produto(p.url, m.nome)",
    ]
    for trecho in exigencias_similares:
        if trecho not in similares:
            return falhar("similares final nao garante: {}".format(trecho))

    _, eventos_recentes = ultima_definicao(
        arquivos, "create or replace function public.eventos_recentes")
    if "public.url_publica_produto(p.url, m.nome)" not in eventos_recentes:
        return falhar("eventos recentes ainda devolvem host administrativo")

    estado_final = "\n".join(
        open(c, encoding="utf-8").read().lower() for c in arquivos)
    exigencias_finais = [
        "unique nulls not distinct (data, fonte, marca_id)",
        "revoke execute on functions from public, anon, authenticated",
        "revoke select on table public.raridade_do_atributo",
    ]
    for trecho in exigencias_finais:
        if trecho not in estado_final:
            return falhar("hardening final ausente: {}".format(trecho))

    _, publicar = ultima_definicao(
        arquivos, "create or replace function public.publicar_atributos")
    exigencias_publicacao = [
        "stage incompleto",
        "produtos_vivos <> p_total",
        "delete from public.produto_termos where origem = 'titulo'",
        "produtos_publicados <> p_total",
        "pg_advisory_xact_lock",
    ]
    for trecho in exigencias_publicacao:
        if trecho not in publicar:
            return falhar("publicacao de atributos nao garante: {}".format(
                trecho))

    _, motor = ultima_definicao(
        arquivos, "create or replace function public.computar_motor")
    passos_motor = [
        "r_eventos := public.computar_eventos()",
        "r_varejo := public.computar_serie_varejo()",
        "r_editorial := public.computar_serie_editorial()",
        "r_z := public.computar_z()",
        "r_indice := public.computar_indice()",
        "r_curva := public.computar_curva_tamanhos()",
        "r_raridade := public.computar_raridade()",
    ]
    posicoes = [motor.find(p) for p in passos_motor]
    if any(p < 0 for p in posicoes) or posicoes != sorted(posicoes):
        return falhar("computar_motor nao preserva a ordem dos sete passos")
    if "revoke execute on function public.computar_motor()" not in motor:
        return falhar("computar_motor ficou executavel publicamente")

    _, lote = ultima_definicao(
        arquivos, "create or replace function public.publicar_motor")
    publicar_pos = lote.find(
        "atributos := public.publicar_atributos(p_execucao, p_total)")
    computar_pos = lote.find("calculos := public.computar_motor()")
    if publicar_pos < 0 or computar_pos <= publicar_pos:
        return falhar("publicar_motor nao une atributos e calculos na ordem")
    if "revoke execute on function public.publicar_motor(uuid, integer)" not in lote:
        return falhar("publicar_motor ficou executavel publicamente")

    _, assinc = ultima_definicao(
        arquivos, "create or replace function public.solicitar_publicacao_motor")
    exigencias_assincronas = [
        "canario-motor-dispatcher",
        "dispatcher do motor nao esta instalado",
        "ja existe uma publicacao do motor em andamento",
        "stage incompleto",
    ]
    for trecho in exigencias_assincronas:
        if trecho not in assinc:
            return falhar("fila assincrona nao garante: {}".format(trecho))

    _, preparo = ultima_definicao(
        arquivos, "create or replace function public.preparar_stage_motor")
    exigencias_preparo = [
        "interval '20 minutes'",
        "where status in ('queued', 'running')",
        "ja existe uma publicacao do motor em andamento",
        "truncate table public.motor_termos_stage, public.motor_produtos_stage",
        "revoke execute on function public.preparar_stage_motor()",
    ]
    for trecho in exigencias_preparo:
        if trecho not in preparo:
            return falhar("preparo reconstruivel nao garante: {}".format(trecho))

    _, worker = ultima_definicao(
        arquivos, "create or replace function public.executar_publicacao_motor")
    exigencias_worker = [
        "set statement_timeout to '900s'",
        "v_resultado := public.publicar_motor(p_execucao, p_total)",
        "status = 'failed'",
    ]
    for trecho in exigencias_worker:
        if trecho not in worker:
            return falhar("worker assincrono nao garante: {}".format(trecho))

    _, dispatcher = ultima_definicao(
        arquivos, "create or replace function public.executar_proxima_publicacao_motor")
    exigencias_dispatcher = [
        "where status = 'queued'",
        "order by solicitado_em",
        "perform public.executar_publicacao_motor(v_execucao, v_total)",
    ]
    for trecho in exigencias_dispatcher:
        if trecho not in dispatcher:
            return falhar("dispatcher nao garante: {}".format(trecho))

    estado_final = "\n".join(
        open(c, encoding="utf-8").read().lower() for c in arquivos)
    if ("set statement_timeout = '900s';" not in estado_final
            or "select public.executar_proxima_publicacao_motor();" not in estado_final):
        return falhar("timeout do cron nao e configurado antes do dispatcher")
    if "set work_mem = '64mb';" not in estado_final:
        return falhar("dispatcher nao reserva memoria para evitar spill")

    _, limite_visao = ultima_definicao(
        arquivos, "create or replace function public._reservar_analise_visual")
    exigencias_limite_visao = [
        "pg_advisory_xact_lock",
        "p_limite_origem",
        "p_limite_global",
        "grant execute on function public._reservar_analise_visual",
        "to service_role",
    ]
    for trecho in exigencias_limite_visao:
        if trecho not in limite_visao:
            return falhar("limite da visao nao garante: {}".format(trecho))

    _, curva = ultima_definicao(
        arquivos, "create or replace function public.computar_curva_tamanhos")
    if "_curva_com_termo" in curva:
        return falhar("curva final ainda materializa a expansao larga")
    if "por_termo as not materialized" not in curva:
        return falhar("curva final ainda pode materializar a expansao por termo")
    if "join produto_termos pt on pt.produto_id = c.produto_id" not in curva:
        return falhar("curva final perdeu o recorte por termo")

    if ("alter table public.motor_termos_stage set unlogged" not in estado_final
            or "alter table public.motor_produtos_stage set unlogged" not in estado_final):
        return falhar("stage temporario ainda gera WAL desnecessario")

    if ("delete from public.motor_termos_stage where execucao = p_execucao" not in worker
            or "delete from public.motor_produtos_stage where execucao = p_execucao" not in worker):
        return falhar("worker nao limpa stage depois de falha")

    print("{} migrations: historico timestampado e estado final protegido".format(
        len(arquivos)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
