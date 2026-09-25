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
        "from public.observacoes_publicadas_do_painel",
        "where segmento in ('feminino_casual_br', 'catalogo_candidato_br')",
        "least(greatest(coalesce($2, 12), 1), 24)",
        "ep.ofertavel is true",
        # A57 trocou a ancora: o frescor e medido contra o ultimo dia
        # observado DO PROPRIO SEGMENTO, nao contra o calendario e nao contra
        # uma data unica para as duas coortes.
        "join painel pa on pa.segmento = p.segmento",
        "ep.ultimo_avistamento_em >= pa.observado_em - 7",
        "ep.ultimo_avistamento_em <= pa.observado_em",
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

    caminho_a57 = next((c for c in arquivos
                        if "20260917210000_a57" in c), None)
    a57 = open(caminho_a57, encoding="utf-8").read().lower()
    exigencias_seed_publicado = [
        "with marcas_esperadas as",
        "from public.marcas m",
        "s.data = d.observado_em",
        "coalesce(s.visitados, 0) > 0",
        "array['truncou', 'faixas_truncadas']",
        "historico.media_positiva_7d is null",
        "s.visitados::numeric\n                     >= historico.media_positiva_7d * 0.30",
        "h.data >= d.observado_em - 7",
        "h.data < d.observado_em",
        "coalesce(h.visitados, 0) > 0",
        "c.marcas_saudaveis = c.marcas_esperadas",
        "raise exception\n      'a57 nao achou observacao completa em saude",
    ]
    for trecho in exigencias_seed_publicado:
        if trecho not in a57:
            return falhar("seed A57 pode aceitar lote parcial: {}".format(trecho))

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

    # P22: as tres escritas de `series_semanais` so gravam o que mudou.
    # Medido em 18/09/2026: 2.728.348 updates em 29.047 linhas, heap com 30,6%
    # de dado vivo. Sem o predicado, qualquer compactacao volta a ser comida
    # nas primeiras publicacoes depois que a coleta voltar.
    exigencias_sem_reescrita = {
        "computar_z": [
            "and s.z is distinct from c.z",
        ],
        "computar_serie_varejo": [
            "where series_semanais.valor_bruto is distinct from excluded.valor_bruto",
            "or series_semanais.z is not null",
            "or series_semanais.n_amostra is distinct from excluded.n_amostra",
            "or (series_semanais.meta - 'computado_em')",
            "is distinct from (excluded.meta - 'computado_em')",
        ],
        "computar_serie_editorial": [
            "and (s.valor_bruto is distinct from n.valor_bruto",
            "or s.meta is distinct from n.meta)",
        ],
    }
    for funcao, trechos in exigencias_sem_reescrita.items():
        _, corpo = ultima_definicao(
            arquivos, "create or replace function public." + funcao)
        for trecho in trechos:
            if trecho not in corpo:
                return falhar("{} voltou a reescrever sem mudanca: {}".format(
                    funcao, trecho))

    # P21: o portao decide pela cota como a plataforma a mede -- a soma de
    # todos os bancos do cluster --, e mostra principal e overhead separados.
    _, uso = ultima_definicao(
        arquivos, "create or replace function public.uso_do_banco")
    exigencias_uso = [
        "from pg_database d",
        "'bytes_da_cota', t.cota",
        "'banco_principal_bytes', t.principal",
        "'overhead_interno_bytes', t.overhead",
        "'bytes', t.cota",
        "revoke execute on function public.uso_do_banco()",
        "grant execute on function public.uso_do_banco() to service_role",
    ]
    for trecho in exigencias_uso:
        if trecho not in uso:
            return falhar("uso_do_banco nao mede a cota: {}".format(trecho))
    if "pg_database_size(current_database())" in uso.split("$function$;")[0] \
            and "from pg_database d" not in uso:
        return falhar("uso_do_banco voltou a medir so o banco principal")

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
        "from public.observacoes_publicadas_do_painel o",
        "where o.segmento = 'feminino_casual_br'",
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

    # P23 e uma mudanca de plataforma, nao apenas uma string de DELETE. Ela
    # precisa falhar antes de agendar se o contrato do pg_cron nao estiver
    # disponivel e, no mesmo statement, provar que terminou com exatamente um
    # job ativo para o banco e o papel que aplicaram a migration.
    caminhos_p23 = [
        c for c in arquivos
        if os.path.basename(c) ==
        "20260917202000_p23_retencao_do_log_do_cron.sql"
    ]
    if len(caminhos_p23) != 1:
        return falhar("migration P23 ausente ou duplicada")
    p23 = open(caminhos_p23[0], encoding="utf-8").read().lower()
    exigencias_p23 = [
        "do $migration$",
        "to_regprocedure('cron.schedule(text,text,text)')",
        "cron.alter_job(bigint,text,text,text,text,boolean)",
        "c.conname = 'jobname_username_uniq'",
        "a.attname::text = any (array[",
        "v_usuario constant text := 'postgres'",
        "current_user <> v_usuario",
        "r.rolcanlogin and (r.rolsuper or r.rolbypassrls)",
        "j.username <> v_usuario",
        "has_table_privilege(\n       v_usuario, 'cron.job_run_details', 'delete')",
        "v_jobid := cron.schedule(v_nome, v_agenda, v_comando)",
        "perform cron.alter_job(v_jobid, active => true)",
        "j.schedule = v_agenda",
        "j.command = v_comando",
        "j.database = v_banco",
        "j.username = v_usuario",
        "j.active is true",
        "v_total <> 1 or v_exatos <> 1",
    ]
    for trecho in exigencias_p23:
        if trecho not in p23:
            return falhar("retencao do cron nao e atomica: {}".format(trecho))

    exigencias_finais = [
        # P23: o log do pg_cron tem retencao. O dispatcher roda a cada minuto
        # e, sem isto, o log cresce ~360 KB por dia com a coleta parada.
        "'canario-retencao-do-log-do-cron'",
        "where end_time < now() - interval '7 days'",
        "and status = 'succeeded'",
        "where end_time < now() - interval '30 days'",
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
        # O maximo gravado por um lote so vira data publica com saude positiva
        # de todas as marcas ativas/testadas do segmento. Isso protege tambem
        # motor manual e coleta dirigida a uma marca.
        "insert into public.observacoes_publicadas_do_painel",
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
    # A60: o motor nao julga cobertura sozinho; pergunta a funcao unica, que
    # espelha `alertas_criticos` do coletor. Um portao por linguagem foi o que
    # travou o painel em 22/09/2026.
    exigencias_publicacao_do_painel = [
        "public.cobertura_de_publicacao(\n      c.segmento, c.observado_em) cp",
        "count(cp.marca_id) filter (where cp.coberta)",
        "co.marcas_cobertas = co.marcas_esperadas",
    ]
    for trecho in exigencias_publicacao_do_painel:
        if trecho not in motor:
            return falhar(
                "motor pode publicar painel parcial: {}".format(trecho))

    _, cobertura = ultima_definicao(
        arquivos, "create or replace function public.cobertura_de_publicacao")
    exigencias_cobertura = [
        # A coorte vem de `marcas`, nao de produtos: marca ativa sem produto
        # ainda precisa comparecer.
        "from public.marcas m",
        "m.segmento = p_segmento",
        "m.ativa is true",
        # Saudavel continua sendo o criterio da A58, linha por linha.
        "l.visitados > 0",
        "array['truncou', 'faixas_truncadas']",
        ">= historico.media_positiva_7d * 0.30",
        "h.data >= l.data - 7",
        "coalesce(h.visitados, 0) > 0",
        # Tolerancia do Python: adiamento declarado e recusa externa conhecida
        # por menos de 3 coletas, sempre com base saudavel nos 7 dias da P17.
        "adiado_por_cadencia",
        "\\yhttp\\s+(429|5[0-9]{2})\\y|robots\\s+proibe",
        "s.data between p_data - 7 and p_data",
        "when not tem_linha then false",
        "when adiada_hoje then ultima_saudavel is not null",
        "when recusa_hoje then ultima_saudavel is not null and falhas < 3",
        "and not f.adiada",
        "revoke all on function public.cobertura_de_publicacao(text, date)",
    ]
    for trecho in exigencias_cobertura:
        if trecho not in cobertura:
            return falhar(
                "cobertura de publicacao nao garante: {}".format(trecho))
    # As duas linguagens precisam mudar juntas: se o coletor passar a tolerar
    # outro numero de zeros, o SQL tem de acompanhar na mesma PR.
    coletor = open(os.path.join(os.path.dirname(__file__), "coletor_varejo.py"),
                   encoding="utf-8").read()
    if "DIAS_DE_ZERO_PARA_BLOQUEAR = 3\n" not in coletor:
        return falhar("tolerancia de zeros do coletor divergiu da A60 (falhas < 3)")

    # A61: marca que troca de plataforma troca de identificadores. O catalogo
    # aposentado nao sai de linha e nao conta duas vezes; o laboratorio prova
    # o efeito, e aqui fica o contrato de texto de cada funcao.
    exigencias_troca = {
        "create or replace function public.computar_eventos": [
            "from public.produtos_de_catalogo_aposentado ca\n"
            "                     where ca.produto_id = u.produto_id);",
        ],
        "create or replace function public.sortimento_observado": [
            "and ca.aposentado_em <= alvo",
        ],
        "create or replace function public.computar_serie_varejo": [
            "left join public.produtos_de_catalogo_aposentado ca on ca.produto_id = p.id",
            "and (e.aposentado_em is null or w.semana + 6 < e.aposentado_em)",
        ],
        "create or replace view public.produtos_de_catalogo_aposentado": [
            "with (security_invoker = true)",
            "where ep.ultimo_avistamento_em < t.em",
        ],
    }
    for cabeca, trechos in exigencias_troca.items():
        _, definicao = ultima_definicao(arquivos, cabeca)
        for trecho in trechos:
            if trecho not in definicao:
                return falhar("troca de catalogo nao garante: {}".format(
                    trecho.splitlines()[-1].strip()))
    # O coletor e as restricoes de `marcas` precisam conhecer as mesmas
    # plataformas: marca num lado so ou nao materializa ou nao e coletada.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import materializar_anexos
    _, restricao = ultima_definicao(
        arquivos, "add constraint marcas_plataforma_check")
    declaradas = set(re.findall(r"'([a-z]+)'", restricao.split(";")[0]))
    if declaradas != set(materializar_anexos.PLATAFORMAS):
        return falhar("plataformas do coletor ({}) e do banco ({}) divergiram".format(
            ", ".join(materializar_anexos.PLATAFORMAS), ", ".join(sorted(declaradas))))
    # A64: o portao de publicacao cobra exatamente quem o coletor coleta. Em
    # 23/09/2026 a Amaro virou `nuvemshop`, passou a ser coletada e ficou fora
    # da cobertura: uma falha dela publicaria o painel em silencio.
    coorte = re.search(r"m\.status_teste in \(([^)]*)\)", cobertura)
    cobradas = set(re.findall(r"'([a-z]+)'", coorte.group(1))) if coorte else set()
    if cobradas != set(materializar_anexos.PLATAFORMAS):
        return falhar("portao de publicacao cobra ({}) e o coletor coleta ({})".format(
            ", ".join(sorted(cobradas)), ", ".join(materializar_anexos.PLATAFORMAS)))
    if 'm.get("status_teste") in ("vtex", "shopify")' in coletor:
        return falhar("portao de saude do Python voltou a ter lista propria de plataformas")

    # A63: o Supabase e o titular do disparo diario. O token do GitHub mora
    # so no Vault, nenhum papel do app alcanca as funcoes, e cada dia tem no
    # maximo um disparo e uma acao da vigia.
    caminho_a63 = next((c for c in arquivos if "_a63_" in c), None)
    if caminho_a63 is None:
        return falhar("A63 (gatilho e vigia do pipeline) sumiu")
    a63 = open(caminho_a63, encoding="utf-8").read()
    for trecho in (
            "from vault.decrypted_secrets",
            "where name = 'github_pipeline'",
            "on conflict (tipo, data_operacional) do nothing;\n  if not found then",
            "revoke all on function public._token_do_github() from public, anon, authenticated, service_role;",
            "revoke all on function public._chamar_github(text, text, jsonb) from public, anon, authenticated, service_role;",
            "revoke all on function public.disparar_pipeline_diario() from public, anon, authenticated, service_role;",
            "revoke all on function public.vigiar_pipeline_diario() from public, anon, authenticated, service_role;",
            "m.segmento = 'feminino_casual_br'",
            "select cron.schedule('canario-disparo-diario', '17 6 * * *'",
            "select cron.schedule('canario-vigia-do-pipeline', '0 15 * * *'",
            "select cron.schedule('canario-respostas-do-github', '27 * * * *'"):
        if trecho not in a63:
            return falhar("gatilho do pipeline nao garante: {}".format(trecho.splitlines()[0]))
    if re.search(r"gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}", a63):
        return falhar("a A63 carrega um token do GitHub no texto")

    # A64: a leitura especifica procura pecas pelo nome. Sinal vindo da Luna
    # e texto escapado, nunca padrao; so peca ativa do painel publicado conta;
    # so a Edge Function (chave de servico) chama.
    caminho_a64 = next((c for c in arquivos if "_a64_candidatas_e_fatos_da_leitura" in c), None)
    if caminho_a64 is None:
        return falhar("A64 (candidatas e fatos da leitura) sumiu")
    a64 = open(caminho_a64, encoding="utf-8").read()
    for trecho in (
            "replace(replace(replace(s, '\\', '\\\\'), '%', '\\%'), '_', '\\_')",
            "where length(s) between 3 and 40",
            "and not (a.t like any (vetos))",
            "ep.ultimo_avistamento_em between painel - 7 and painel",
            "from public.produtos_de_catalogo_aposentado ca",
            "revoke all on function public.candidatas_da_leitura(text[], text[], text[], integer) from public, anon, authenticated;",
            "revoke all on function public.fatos_da_leitura(bigint[], numeric) from public, anon, authenticated;"):
        if trecho not in a64:
            return falhar("leitura especifica nao garante: {}".format(trecho))
    if a64.count("ep.ultimo_avistamento_em between painel - 7 and painel") < 2:
        return falhar("candidatas e fatos precisam da mesma janela de peca ativa")
    _, candidatas = ultima_definicao(
        arquivos, "create or replace function public.candidatas_da_leitura(")
    for trecho in (
            "p_atributos text[]",
            "public._texto_da_leitura(p_sinais)",
            "and not (a.t like any (vetos))",
            "ep.ultimo_avistamento_em between painel - 7 and painel",
            "from public.produtos_de_catalogo_aposentado ca",
            "where not exists (select 1 from public.produto_termos pt",
            "revoke all on function public.candidatas_da_leitura(text[], text[], text[], text[], integer) from public, anon, authenticated;"):
        if trecho not in candidatas:
            return falhar("candidatas finais da leitura nao garantem: {}".format(trecho))
    caminho_a67 = next((c for c in arquivos if "_a67_" in c), None)
    a67 = open(caminho_a67, encoding="utf-8").read() if caminho_a67 else ""
    for trecho in ("check (chave ~ '^[0-9a-f]{64}$')",
                   "revoke all on public.interpretacoes_da_leitura from public, anon, authenticated;",
                   "where criado_em < now() - interval '7 days'"):
        if trecho not in a67:
            return falhar("interpretacao estavel da leitura nao garante: {}".format(trecho))
    caminho_a68 = next((c for c in arquivos if "_a68_veredictos_da_leitura_estaveis" in c), None)
    a68 = open(caminho_a68, encoding="utf-8").read() if caminho_a68 else ""
    if "add column if not exists veredictos jsonb not null default '{}'::jsonb" not in a68:
        return falhar("veredictos estaveis da leitura sumiram (A68)")

    _, poda = ultima_definicao(
        arquivos, "create or replace function public.podar_snapshots")
    exigencias_poda = [
        "p_retencao_dias integer default 21",
        "p_retencao_dias < 21",
        "data < (current_date - p_retencao_dias)",
        "revoke execute on function public.podar_snapshots(integer)",
        # P24: enquanto a A58 nao existir, o cru e a unica fonte do
        # denominador. Medido em 18/09/2026: a primeira poda depois da
        # retomada apagaria 202.050 de 254.736 linhas -- 16 dos 22 dias.
        "if to_regclass('public.sortimento_diario') is null then",
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
    # A62: a curva olha so a vitrine. Medido em 23/09/2026: 81.620 produtos na
    # base do feminino, 28.811 na vitrine; share indisponivel de 74,8% para
    # 43,2%. O laboratorio prova o efeito e reprova dez mutacoes; aqui fica o
    # texto de cada regra.
    exigencias_vitrine = [
        # Ancora por segmento, no dado (A57): pausa nao e ausencia.
        "join _curva_ancora a on a.segmento = p.segmento",
        "ep.ultimo_avistamento_em >= a.observado_em - 7",
        # Segmento parado de vez nao ganha a semana nova com a foto velha.
        "having max(ep.ultimo_avistamento_em) > (semana_alvo + 6) - janela_dias",
        # Catalogo trocado de plataforma nao e sortimento (A61).
        "and not exists (select 1 from public.produtos_de_catalogo_aposentado ca\n"
        "                       where ca.produto_id = p.id)",
        # A venda hoje OU em algum dia da janela: quem esgotou na janela e a
        # quebra; so "ofertavel hoje" tirava 775 quebras da manchete.
        "(ep.ofertavel is true",
        "and s.ofertavel is true",
        # A semana alvo e refeita inteira; as publicadas ficam.
        "where c.semana = semana_alvo",
        "'base_observada_em', an.observado_em",
        "revoke all on function public.computar_curva_tamanhos(integer)",
    ]
    for trecho in exigencias_vitrine:
        if trecho not in curva:
            return falhar("curva nao se limita a vitrine: {}".format(trecho))
    if "current_date" in curva:
        return falhar("curva ancora a base no calendario, nao no dado")
    # A68: a curva mede a janela que observou. Medido em 23/09/2026, janela de
    # 19 a 23/09: a regra antiga achava 1.614 quebras (4,92%); partindo da
    # ultima foto ate o primeiro dia, 5.478 (6,13%). O laboratorio reprova
    # oito mutacoes; aqui fica o texto de cada regra.
    exigencias_janela = [
        # Dias de coleta saudavel da marca, com a linha da A58/A60.
        "from saude s",
        "and not (l.alertas ?| array['truncou', 'faixas_truncadas'])",
        "or l.visitados::numeric >= historico.media_positiva_7d * 0.30)",
        # Marca com uma coleta so nao tem o que comparar.
        "having max(data) > min(data)",
        # Estado do inicio: a ultima foto ate o primeiro dia, de no maximo
        # seis dias, de peca vista dali em diante.
        "where s.data <= m.inicio",
        "and s.data > m.inicio - 7",
        "where ep.ultimo_avistamento_em >= mj.inicio",
        # A tela declara a janela real, nao os 14 nominais.
        "'janela_observada'",
        "'dias', js.fim - js.inicio,",
    ]
    for trecho in exigencias_janela:
        if trecho not in curva:
            return falhar("curva nao mede a janela observada: {}".format(trecho))
    if "first_value(t.value = 'true'::jsonb) over w" in curva:
        return falhar("curva voltou a ler so as fotos de dentro da janela")

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
