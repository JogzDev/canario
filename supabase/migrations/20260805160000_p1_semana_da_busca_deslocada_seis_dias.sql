-- Corrige o rotulo de semana de TODA a perna de busca ja coletada.
--
-- O QUE ESTAVA ERRADO
-- ===================
--
-- O Google Trends marca cada semana pelo DOMINGO em que ela comeca. O coletor
-- fazia `quando - timedelta(days=quando.weekday())` para "normalizar para
-- segunda ISO"; `weekday()` de domingo e 6, entao a linha subtraia seis dias e
-- jogava o ponto para a segunda ANTERIOR -- fora do periodo que ele mede. A
-- semana de 26/07 a 01/08 foi gravada como "semana de 20/07".
--
-- O editorial usa `date_trunc('week')`, que da segunda ISO de verdade. Entao o
-- mesmo rotulo "semana de 20/07" significava 20-26/07 numa perna e 26/07-01/08
-- na outra: seis dias de deslocamento, UM dia em comum. A §22 so afirma
-- direcao quando as duas pernas concordam na mesma semana, e vinha comparando
-- semanas quase disjuntas -- em silencio, em toda leitura do app, desde o
-- primeiro dia da perna de busca.
--
-- Sao 10.460 linhas, 40 termos, de 19/07/2021 a 20/07/2026.
--
-- POR QUE +7 DIAS
-- ===============
--
-- O ponto gravado em D veio do domingo S = D + 6 e mede S..S+6. A semana ISO
-- que mais cobre esse periodo comeca na segunda S+1 = D+7, com 6 dos 7 dias em
-- comum. Antes eram 1 de 7.
--
-- Fica UM dia de imprecisao, e ele e inerente: o Google conta a semana de
-- domingo a sabado, o resto do projeto de segunda a domingo. Some sozinho a
-- medida que a coleta nova -- montada dia a dia, em semana ISO exata --
-- sobrescreve as 34 semanas mais recentes.
--
-- EM DUAS ETAPAS, DE PROPOSITO
-- ============================
--
-- A chave unica e (termo_id, segmento, fonte, semana). Somar 7 de uma vez faz
-- cada linha pousar na semana da linha seguinte antes que ela saia do lugar, e
-- o indice recusa. O desvio por 10.000 dias (~2053, onde nao ha nada) tira
-- todas do caminho primeiro. Preserva os ids, ao contrario de apagar e
-- reinserir.

update public.series_semanais
   set semana = semana + 10000
 where fonte = 'busca';

update public.series_semanais
   set semana = semana - 9993,
       -- O z foi calculado sobre semanas erradas: nao da para reaproveitar.
       -- `computar_z()` refaz, e `computar_indice()` apaga indice sem base.
       z = null,
       meta = coalesce(meta, '{}'::jsonb) || jsonb_build_object(
                'rotulo_corrigido', '+7d',
                'rotulo_corrigido_em', current_date,
                'motivo', 'semana do Trends comeca no domingo; o coletor '
                          'jogava o ponto para a segunda anterior')
 where fonte = 'busca';
