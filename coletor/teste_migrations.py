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

    # A57 NAO substitui as funcoes antigas: quem decide a versao do app
    # instalada e a pessoa, e trocar o comportamento por baixo de um aparelho
    # que ninguem atualizou muda a tela de quem nao pediu para mudar. A v1
    # fica congelada na A40 -- inclusive com o defeito da ancora de
    # calendario, que e o que o app ja instalado espera receber.
    arquivo_v1, similares_v1 = ultima_definicao(
        arquivos, "create or replace function public.similares_da_peca(")
    if "20260917210000_a57" in arquivo_v1:
        return falhar("a A57 voltou a substituir similares_da_peca no lugar")
    if "ep.ultimo_avistamento_em >= current_date - 7" not in similares_v1:
        return falhar("a v1 de similares deixou de ser a da A40")
    for proibido in ("join painel pa", "'visto_em', visto_em"):
        if proibido in similares_v1:
            return falhar(
                "a v1 de similares ganhou contrato novo: {}".format(proibido))

    _, similares = ultima_definicao(
        arquivos, "create or replace function public.similares_da_peca_v2(")
    exigencias_similares = [
        "t.status = 'aprovado'",
        "limit 12",
        "p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')",
        "least(greatest(coalesce($2, 12), 1), 24)",
        "ep.ofertavel is true",
        # A57 trocou a ancora: o frescor e medido contra o ultimo dia
        # observado DO PROPRIO SEGMENTO, nao contra o calendario e nao contra
        # uma data unica para as duas coortes.
        "join painel pa on pa.segmento = p.segmento",
        "ep.ultimo_avistamento_em >= pa.observado_em - 7",
        "coalesce(g.esgotada, false) = false",
        "public.url_publica_produto(p.url, m.nome)",
        "cardinality(par.categorias) = 0",
        "bool_or(e.dimensao = 'categoria') as tem_categoria",
    ]
    for trecho in exigencias_similares:
        if trecho not in similares:
            return falhar("similares final nao garante: {}".format(trecho))

    # A57: pausa de coleta nao pode virar "nao existe peca parecida". Medido em
    # 17/09/2026, com a coleta parada desde 02/09: similares devolvia 0 para
    # `vestido + preto` num painel com 12.496 vestidos.
    exigencias_frescor = [
        "group by p.segmento",
        "'visto_em', visto_em",
        "'observado_em', max(visto_em)",
        "'observado_mais_antigo_em', min(visto_em)",
        "'dias_desde_a_observacao', (current_date - max(visto_em))",
        # A ponta VELHA e quem decide se o conjunto pode ser chamado de
        # "agora": uma peca vista ontem nao pode carimbar de atual outra
        # vista ha oito dias na mesma resposta.
        "'dias_desde_a_observacao_mais_antiga', (current_date - min(visto_em))",
        # Zero resultado tambem tem periodo: a data do painel consultado nao
        # depende de ter havido casamento.
        "'painel_observado_em', (select observado_em from painel",
        "'painel_dias_desde_a_observacao'",
    ]
    for trecho in exigencias_frescor:
        if trecho not in similares:
            return falhar("similares nao ancora frescor no dado: {}".format(trecho))
    if "ep.ultimo_avistamento_em >= current_date - 7" in similares:
        return falhar("similares ainda ancora frescor em current_date")

    _, similares_amplos = ultima_definicao(
        arquivos, "create or replace function public.similares_da_peca_amplo(")
    exigencias_amostra_util = [
        "jsonb_array_length(coalesce(estrita->'pecas'",
        "t.dimensao <> 'categoria'",
        "dimensao_relaxada",
        "public.similares_da_peca(termos_reduzidos",
        "grant execute on function public.similares_da_peca_amplo",
    ]
    for trecho in exigencias_amostra_util:
        if trecho not in similares_amplos:
            return falhar("amostra ampliada nao garante: {}".format(trecho))

    # O envelope e o que o app chama de verdade. Se ele continuasse caindo na
    # v1, a v2 existiria sem ninguem para consumi-la.
    _, amplo_v2 = ultima_definicao(
        arquivos, "create or replace function public.similares_da_peca_amplo_v2(")
    exigencias_amplo_v2 = [
        "public.similares_da_peca_v2(termos, limite, preco_alvo)",
        "public.similares_da_peca_v2(termos_reduzidos",
        "dimensao_relaxada",
        "grant execute on function public.similares_da_peca_amplo_v2",
    ]
    for trecho in exigencias_amplo_v2:
        if trecho not in amplo_v2:
            return falhar("envelope v2 nao garante: {}".format(trecho))

    _, serie_varejo = ultima_definicao(
        arquivos, "create or replace function public.computar_serie_varejo")
    exigencias_presenca = [
        "ep.ultimo_avistamento_em",
        "e.ofertavel is true",
        "s.data + 6",
        "lead(s.data) over",
        "legado_desconhecido_excluido",
        "delete from public.series_semanais",
        "serie de varejo vazia",
        "cobertura_dimensao_pct",
        "n_com_atributo_na_dimensao",
        "t.papel in ('atributo', 'denominador')",
        "s.semana >= (select min(semana) from _serie_varejo_nova)",
    ]
    for trecho in exigencias_presenca:
        if trecho not in serie_varejo:
            return falhar("serie de varejo final nao garante: {}".format(
                trecho))

    _, cobertura = ultima_definicao(
        arquivos, "create or replace view public.cobertura_por_celula")
    exigencias_cobertura = [
        "security_invoker = true",
        "cobertura_dimensao_pct",
        "minimo_cobertura_dimensao_pct",
        ">= 30",
        "coalesce(",
    ]
    for trecho in exigencias_cobertura:
        if trecho not in cobertura:
            return falhar("portao de cobertura final nao garante: {}".format(
                trecho))

    _, raridade = ultima_definicao(
        arquivos, "create or replace function public.computar_raridade")
    exigencias_raridade_atual = [
        "ativos as materialized",
        "ep.ofertavel is true",
        "ep.ultimo_avistamento_em >=",
        "at time zone 'America/Sao_Paulo'",
    ]
    for trecho in exigencias_raridade_atual:
        if trecho not in raridade:
            return falhar(
                "raridade final ainda usa catalogo historico: {}".format(
                    trecho))

    _, eventos_recentes = ultima_definicao(
        arquivos, "create or replace function public.eventos_recentes")
    if "public.url_publica_produto(p.url, m.nome)" not in eventos_recentes:
        return falhar("eventos recentes ainda devolvem host administrativo")
    # A57: o link e decidido pelo estado que o coletor escreve. A coluna
    # `produtos.ultimo_snapshot_em` congelou em 24/08/2026, quando a A27 moveu
    # o estado para `estado_dos_produtos` -- o link teria sumido em 07/09
    # mesmo com a coleta de pe.
    if "ep.ultimo_snapshot_em" not in eventos_recentes:
        return falhar("link da loja ainda le a coluna congelada de produtos")
    if "current_date - 14" in eventos_recentes:
        return falhar("link da loja ainda ancora frescor em current_date")

    _, resumo_eventos = ultima_definicao(
        arquivos, "create or replace function public.resumo_de_eventos")
    exigencias_resumo = [
        # A unidade da manchete e produto distinto. A capa contava EVENTOS de
        # uma amostra de 120: em 01/09 deu a capa a C&A com 52 enquanto a Le
        # Lis Blanc tinha 289 na populacao inteira do dia.
        "count(distinct np.produto_id)::int as pecas",
        # Janela explicita e ancorada no dado, nunca em current_date.
        "lim.ate - (par.janela - 1) as de",
        # Denominador por marca: sem ele, "quem repos mais" premia catalogo.
        # Denominador observado no fim da janela, materializado; nunca o
        # estado do momento da consulta.
        "join public.sortimento_diario sd",
        "on sd.data = j.ate and sd.segmento = 'feminino_casual_br'",
        "'denominador_em'",
        "por_mil_ofertadas",
        # Exemplos sao amostra e nao podem voltar a alimentar contagem, nem
        # gastar dois cartoes com a mesma peca que repos duas vezes.
        "x.posicao <= j.teto",
        "select distinct on (np.produto_id) np.*",
        # O sinal de repeticao que o JP pediu em 31/07 ("3a reposicao dos
        # tamanhos PP/P em menos de 2 meses") viajava em `eventos_recentes`.
        # Como a tela deixa de contar por ali, ele passa a viajar no exemplo.
        "'ordinal', h.ordinal",
        "'dias_desde_a_primeira', h.dias_desde_a_primeira",
        "'detalhe', e.detalhe",
        # Janela COMUM aos tres tipos, ancorada na observacao do painel ou num
        # `ate` explicito de quem pergunta.
        "ate date default null",
        "max(ep.ultimo_avistamento_em)",
        "grant execute on function public.resumo_de_eventos(text, integer, integer, date)",
    ]
    for trecho in exigencias_resumo:
        if trecho not in resumo_eventos:
            return falhar("resumo de eventos nao garante: {}".format(trecho))
    # Ancorar no ultimo evento DE CADA TIPO fazia "nenhuma remarcacao nesta
    # semana" recuar ate a ultima remarcacao e apresenta-la como atual.
    if "max(e.data)" in resumo_eventos:
        return falhar("a janela voltou a seguir o ultimo evento do tipo")

    _, referencia = ultima_definicao(
        arquivos,
        "create or replace function public.buscar_referencia_editorial")
    exigencias_referencia = [
        # Expressao do usuario e dado, nao padrao de LIKE.
        "replace(replace(replace(termo, '\\', '\\\\'), '%', '\\%'), '_', '\\_')",
        # Mesmo recorte de publico que o painel admite.
        "a.publico_editorial <> 'masculino'",
        # Sem select geral em artigos: a funcao devolve titulo/veiculo/data/URL.
        "security definer",
        "grant execute on function public.buscar_referencia_editorial(text, integer)",
    ]
    for trecho in exigencias_referencia:
        if trecho not in referencia:
            return falhar("busca editorial nao garante: {}".format(trecho))

    _, produto_por_url = ultima_definicao(
        arquivos, "create or replace function public.produto_do_painel_por_url")
    exigencias_url = [
        "length(p_url) > 2048",
        "p_url !~ '^https://[^/]+/'",
        "p.segmento in ('feminino_casual_br', 'catalogo_candidato_br')",
        "ep.ofertavel is true",
        "ep.ultimo_avistamento_em >= current_date - 7",
        "grant execute on function public.produto_do_painel_por_url(text)",
    ]
    for trecho in exigencias_url:
        if trecho not in produto_por_url:
            return falhar("entrada por URL nao garante: {}".format(trecho))

    estado_final = "\n".join(
        open(c, encoding="utf-8").read().lower() for c in arquivos)
    exigencias_finais = [
        "unique nulls not distinct (data, fonte, marca_id)",
        "revoke execute on functions from public, anon, authenticated",
        "revoke select on table public.raridade_do_atributo",
        "('claudia', 'editorial_br')",
        "('fashion gone rogue', 'editorial_intl')",
        "('red carpet fashion awards', 'editorial_intl')",
        # A58: a tabela do denominador nao e legivel por anon -- entra pela
        # RPC -- e a reconstrucao diaria escreve so o que mudou (P11).
        "revoke all on table public.sortimento_diario from anon, authenticated",
        "revoke all on function public.computar_sortimento_diario(date) from public, anon, authenticated",
        "is distinct from excluded.pecas_ofertadas",
        # P17: o snapshot vale sete dias. Sem o piso, catalogo morto contava
        # como oferta para sempre e o denominador inchava.
        "where s.data between alvo - 6 and alvo",
        # Recomputar um dia tambem corrige para baixo: grupo que sumiu do
        # calculo sai da tabela, em vez de virar denominador fantasma.
        "delete from public.sortimento_diario sd",
        "not exists (select 1 from pg_temp.sortimento_calculado c",
        # A coleta e o motor chamam com a chave de servico. Sem o grant a
        # funcao existe e nao roda.
        "grant execute on function public.computar_sortimento_diario(date) to service_role",
        # Sem argumento, alcanca o dia que uma noite vermelha deixou para tras:
        # depois da poda aquele dia nao existe mais.
        "or not exists (select 1 from public.sortimento_diario sd",
    ]
    for trecho in exigencias_finais:
        if trecho not in estado_final:
            return falhar("hardening final ausente: {}".format(trecho))

    _, publicar = ultima_definicao(
        arquivos, "create or replace function public.publicar_atributos")
    exigencias_publicacao = [
        "stage incompleto",
        "produtos_vivos <> p_total",
        # Ate o P12 esta garantia era o literal
        # "delete from public.produto_termos where origem = 'titulo'".
        # O apaga-tudo saiu, mas o que ele protegia continua: o motor so mexe
        # em ligacao de origem 'titulo'. Isso agora vive nas duas anti-juncoes,
        # e esta exigido abaixo por "pt.origem = 'titulo'".
        "delete from public.produto_termos pt",
        # A completude e conferida contra p_total. Ate o P11 isso era medido
        # pelo numero de linhas ATUALIZADAS, o que so funcionava porque todas
        # eram atualizadas sempre; agora e medido pela cobertura do stage,
        # antes de escrever. A garantia e a mesma, na variavel certa.
        "produtos_cobertos <> p_total",
        "pg_advisory_xact_lock",
        # P11: escrever so o que mudou. Reescrever os 82 mil produtos toda
        # noite para gravar o mesmo `segmento` levou o banco de 75% a 97% numa
        # unica coleta, em 19/08/2026. `is distinct from` e obrigatorio: 10,8%
        # dos segmentos sao NULL, e `<>` com NULL devolve NULL, o que
        # descartaria exatamente as linhas que entram ou saem de nulo.
        "p.segmento is distinct from s.segmento",
        # P10: truncate devolve as paginas de indice; delete as deixa alocadas.
        "truncate table public.motor_termos_stage",
        # P12: ligacoes diferenciais. Apagar e reinserir as 208 mil toda noite
        # reinchava heap e indice de produto_termos em ~27 MiB por ciclo.
        "get diagnostics ligacoes_removidas = row_count",
        "get diagnostics ligacoes_inseridas = row_count",
        # O escopo por origem e o que impede o motor de apagar ligacao de
        # visao ou de curadoria manual, que nao sao dele.
        "pt.origem = 'titulo'",
        # Sem estatistica no stage o planejador escolhe Nested Loop com Seq
        # Scan e o motor trava. Medido em 19/08/2026.
        "analyze public.motor_termos_stage",
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
        # A58: ultima leitura do cru antes da poda. Dia podado e dia
        # irreconstruivel -- esta ordem e uma porta de sentido unico.
        "r_sortimento := public.computar_sortimento_diario()",
        "r_snapshots_removidos := public.podar_snapshots(21)",
    ]
    posicoes = [motor.find(p) for p in passos_motor]
    if any(p < 0 for p in posicoes) or posicoes != sorted(posicoes):
        return falhar("computar_motor nao preserva a ordem dos passos")
    if "revoke execute on function public.computar_motor()" not in motor:
        return falhar("computar_motor ficou executavel publicamente")

    _, poda = ultima_definicao(
        arquivos, "create or replace function public.podar_snapshots")
    exigencias_poda = [
        "p_retencao_dias integer default 21",
        "p_retencao_dias < 21",
        "data < (current_date - p_retencao_dias)",
        "revoke execute on function public.podar_snapshots(integer)",
    ]
    for trecho in exigencias_poda:
        if trecho not in poda:
            return falhar("retencao de snapshots nao garante: {}".format(
                trecho))

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
