-- A41: o motor normaliza as séries pelo mapa SQL. Acrescentar a fonte apenas
-- no CSV faria o numerador novo entrar pelo coletor enquanto o denominador a
-- ignoraria na publicação atômica seguinte.

insert into public.veiculo_da_perna (veiculo, fonte) values
  ('Claudia', 'editorial_br'),
  ('Marie Claire US', 'editorial_intl'),
  ('The Zoe Report', 'editorial_intl'),
  ('W Magazine', 'editorial_intl'),
  ('Glamour US', 'editorial_intl'),
  ('Fashion Gone Rogue', 'editorial_intl'),
  ('Fashion Bomb Daily', 'editorial_intl'),
  ('Tom and Lorenzo', 'editorial_intl'),
  ('Fashion Week Daily', 'editorial_intl'),
  ('Red Carpet Fashion Awards', 'editorial_intl')
on conflict (veiculo) do update set fonte = excluded.fonte;
