# Auditoria dos links exibidos pelo app

- URLs únicas testadas: **262**
- Sem sinal técnico de problema: **183**
- Pedem revisão: **79**

O teste segue redirects e verifica status, tipo de imagem, queda na home,
página de erro/esgotado e presença mínima do título no HTML. Uma página
renderizada só por JavaScript pode gerar `titulo_sem_confirmacao` sem estar quebrada.

## Revisar

| marca | superfície | tipo | status | sinais | URL final |
|---|---|---|---:|---|---|
| Maria Filo | evento_reposicao | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fvestido-curto-estampa-sicilia-est-sicilia---15-17954-27758%252Fp |
| Maria Filo | evento_reposicao | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fcalca-jeans-black-barrel-jeans-black-escuro-15-26420-2291%252Fp |
| Dress To | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/calca-estampa-mar-aberto-03130637-471/p |
| Dress To | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/colete-linho-botoes-frente-08220093-2275/p |
| Maria Filo | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fvestido-midi-decote-recorte-preto-15-25690-0005%252Fp |
| Maria Filo | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fcalca-pantalona-detalhe-franzido-rock-15-27111-07535%252Fp |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/blusao-unissex-de-moletom-com-capuz-mindset-working-title-cinza--1113925-cinza_mes1/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-feminina-de-poliuretano-balone-marrom-1108352-marrom_esc/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-militar-feminina-jeans-mindset-azul-1119133-jeans-md/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-feminina-de-suede-com-bolsos-bege-1108380-kaki/p |
| Farm | evento_remarcacao | produto | 404 | http_404, titulo_sem_confirmacao | https://secure.farmrio.com.br/Sistema/404?ProductLinkNotFound=blusa-estampada-posto-6-posto-6_ow-368581-57776 |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-feminina-poliamida-funnel-neck-com-bolsos-bege-1112023-beige_7/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/blusao-feminino-de-moletom-com-capuz-mickey-off-white-1059855-off_white/p |
| Dress To | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/calca-cargo-alfaiataria-03130665-2204/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/blusao-feminino-de-moletom-stitch-com-capuz-azul-1064366-azul_escu/p |
| Lanca Perfume | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.lancaperfume.com.br/regata-canelada-com-bordado-brasil-502rg001313/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/blazer-de-alfaiataria-feminino-com-ombreiras-acetinado-amarelo-1111508-amarelo_c1/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-dupla-face-feminina-de-pu-e-veludo-cotele-mindset-preta-1108423-preto/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/casaco-longo-feminino-com-bolsos-cinza-1103949-preto/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/casaco-sobretudo-feminino-xadrez-azul-1102818-azul_escu/p |
| C&A | evento_remarcacao | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/jaqueta-feminina-de-veludo-cotele-com-bolsos-marrom-1103965-caramelo/p |
| Cantao | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/vestido-alcinha-linho-bordado-etnico-540905031/p |
| Animale | similar_vestido+geometrica | produto | 404 | http_404, titulo_sem_confirmacao | https://www.animale.com.br/vestido-de-tule-longo-poa-preto-manga-comprida-preto-07-20-6195-0005/p |
| Bo.Bo | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.bobo.com.br/chemise-samanta-poa-longo-bo-bo-feminino-preto-15-01-2783/p |
| Maria Filo | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fvestido-poa-mini-preto-15-19035-0005%252Fp |
| Dress To | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/vestido-cropped-estampa-poa-folhagem-01342727-471/p |
| C&A | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/vestido-com-estampa-abstrata-preto-8012991-preto/p |
| Zinzane | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/vestido-midi-manga-curta-poa-rosa-034170-0012/p |
| Dress To | similar_vestido+geometrica | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/vestido-balone-estampa-poa-folhagem-01342679-471/p |
| Cantao | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/blusa-algodao-listra-bordado-dadinho-541483031/p |
| Bo.Bo | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.bobo.com.br/camisa-cora-stripes-bo-bo-feminina-marrom-escuro-13-01-6495/p |
| Le Lis Blanc | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.lelis.com.br/camisa-listrada-le-lis-jaqueline-feminina-listrado-5-13-01-6553/p |
| Maria Filo | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fcamisa-listrada-linho-listrado-15-27910-0015%252Fp |
| Dress To | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/camisa-algodao-listras-lurex-02083268-011/p |
| C&A | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/camisa-feminina-de-algodao-com-pregas-listrada-bege--1103270-bege_l/p |
| Lanca Perfume | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.lancaperfume.com.br/camisa-regular-listrada-de-algodao-502ca001820/p |
| Zinzane | similar_camisa+listra | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/camisa-manga-longa-listras-azul-marinho-033659-1055/p |
| Cantao | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/t-shirt-classic-faz-de-conta-preto-541769021/p |
| Bo.Bo | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.bobo.com.br/regata-ember-preta-tricot-bo-bo-feminina-preto-12-18-1306/p |
| Le Lis Blanc | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.lelis.com.br/blusa-le-lis-lica-preta-seda-feminina-preto-11-03-4547/p |
| Maria Filo | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fregata-flame-black-preto-15-26679-0005%252Fp |
| Morena Rosa | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.morenarosa.com.br/blusa-morena-rosa-ajustada-gola-alta-manga-longa-padrao-preto-375776/p |
| NV | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.bynv.com.br/t-shirt-karen-preto-v272802-nv089/p |
| Dress To | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/blusa-jeans-pespontos-black-02083787-352/p |
| C&A | similar_blusa_top+preto | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/top-esportivo-feminino-de-poliamida-alca-fina-preto-1115471-preto/p |
| C&A | similar_casaco_jaqueta+cinza | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/sueter-de-tricot-com-perolas-cinza-1067811-cinza/p |
| Lanca Perfume | similar_casaco_jaqueta+cinza | produto | 200 | titulo_sem_confirmacao | https://www.lancaperfume.com.br/blazer-regular-em-alfaiataria-mescla-502bz001078/p |
| Zinzane | similar_casaco_jaqueta+cinza | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/casaco-botoes-cinza-034047-0016/p |
| Amaro | similar_casaco_jaqueta+cinza | produto | 200 | esgotado_na_loja | https://amaro.com/products/jaqueta-com-botao-de-la-acrilica-cinza-mescla-claro |
| NV | similar_casaco_jaqueta+cinza | produto | 200 | titulo_sem_confirmacao | https://www.bynv.com.br/blazer-nine-alfa-cinza-mescla-v271969-nv032/p |
| Cantao | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/calca-liocel-ilha-dos-sonhos-amarelo-540502441/p |
| Morena Rosa | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.morenarosa.com.br/conjunto-morena-rosa-blusa-sem-manga-calca-reta-cintura-alta-amarelo-381400/p |
| Morena Rosa | similar_calca+amarelo_laranja | imagem | 404 | http_404, nao_e_imagem | https://lojamorenarosa.vteximg.com.br/arquivos/ids/432059/CONJUNTO-BLUSA-SEM-MANGA-CALCA-RETA-CINTURA-ALTA---AMARELO---P.jpg?v=639208582488730000 |
| NV | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.bynv.com.br/calca-new-helena-laranja-flame-v252906-nv291/p |
| C&A | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/calca-cenoura-feminina-com-linho-e-cinto-laranja-1091250-ocre/p |
| Zinzane | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/calca-pantalona-detalhe-pesponto-amarelo-031667-0008/p |
| Amaro | similar_calca+amarelo_laranja | produto | 404 | http_404, titulo_sem_confirmacao | https://amaro.com/products/calca-wide-leg-de-viscose-ocre |
| Bo.Bo | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.bobo.com.br/calca-philipa-butter-couro-bo-bo-feminina-amarelo-claro-18-14-0318/p |
| Cantao | similar_calca+amarelo_laranja | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/calca-sarja-i-reta-basic-amarelo-5418240377/p |
| Cantao | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/saia-estampada-floral-glitch-540553031/p |
| Dress To | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/saia-midi-linho-bordado-flores-05260597-2342/p |
| C&A | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macaquinho-short-saia-feminino-estampado-floral-com-sobreposicao-alca-fina-preto-9957260-preto/p |
| Lanca Perfume | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.lancaperfume.com.br/short-saia-estampa-floral-502sh001442/p |
| Zinzane | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/short-saia-laise-floral-branco-031700-0001/p |
| Dress To | similar_saia+floral | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/saia-midi-linho-bordado-floral-05260651-198/p |
| Cantao | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.cantao.com.br/bermuda-classic-blue-jeans-5415403172/p |
| Bo.Bo | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.bobo.com.br/bermuda-phillipa-waffle-blue-jeans-bo-bo-feminina-jeans-medio-17-08-1610/p |
| Maria Filo | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://mariafilo.vtexcommercestable.com.br/admin/login/?portal=true&ReturnUrl=%2Fadmin%2Fsite%2FLogin.aspx%3FReturnUrl%3D%252Fshort-estampa-blues-est-blues---15-24038-51854%252Fp |
| Morena Rosa | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.morenarosa.com.br/bermuda-morena-rosa-reta-alta-azul-376485/p |
| NV | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.bynv.com.br/short-heritage-reebok-nv-blue-v262297-nv965/p |
| Dress To | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.dressto.com.br/short-jeans-boyfriend-blue-04300733-352/p |
| C&A | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macaquinho-short-saia-feminino-jeans-azul-1108968-jeans-md/p |
| Zinzane | similar_short+azul | produto | 200 | titulo_sem_confirmacao | https://www.zinzane.com.br/short-bolso-laterais-azul-claro-031494-1002/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macacao-em-algodao-feminino-branco-branco-7829483-branco/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macacao-em-algodao-feminino-tomara-que-caia-branco-7829465-branco/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macaquinho-de-malha-feminino-liso-verde-7690692-verde/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macaquinho-de-malha-feminino-liso-pink-7690692-pink/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macaquinho-de-malha-feminino-liso-amarelo-7690692-amarelo/p |
| C&A | similar_macacao+liso | produto | 200 | titulo_sem_confirmacao | https://www.cea.com.br/macacao-em-poliester-feminino-com-renda-preto-7693242-preto/p |
