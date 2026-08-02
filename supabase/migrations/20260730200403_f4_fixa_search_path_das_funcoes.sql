-- O advisor de seguranca apontou `function_search_path_mutable` nas tres
-- funcoes do motor. Sem search_path fixo, quem chama a funcao pode manipular a
-- resolucao de nomes e fazer a funcao usar uma tabela diferente da pretendida.
-- Fixar em public + pg_temp fecha isso.
alter function computar_serie_varejo() set search_path = public, pg_temp;
alter function computar_z()            set search_path = public, pg_temp;
alter function computar_indice()       set search_path = public, pg_temp;;
