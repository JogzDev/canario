# Dados fictícios em uso

**Exigido pela regra inviolável 2:** *"Todo dado fictício usado em desenvolvimento
deve estar visualmente marcado como fictício na interface e listado no arquivo
`DADOS_FICTICIOS.md` na raiz do repositório."*

E pelo §35: *"Dado fictício vazando para demo → tarefa zero, `DADOS_FICTICIOS.md`
e checagem obrigatória do arquivo antes de qualquer apresentação."*

---

## Estado em 30/07/2026

**Nenhum dado fictício em uso.** A lista está vazia, e vazia é o estado desejado.

Tudo que existe no banco foi coletado pelo próprio sistema, de fonte pública,
com origem e data de coleta registradas:

| Fonte | Origem | Verificável em |
|---|---|---|
| Varejo | catálogo público de 15 marcas (VTEX e Shopify) | `produtos.url`, `snapshots.capturado_em` |
| Busca | Google Trends, geo BR, 5 anos | `series_semanais.meta` (geo, intervalo, âncora, data) |
| Editorial | feeds RSS/Atom de 17 veículos | `artigos.url`, `artigos.data_pub` |

Isso cumpre o critério de sucesso 4 do §9: *"A demo roda com dado real coletado
pelo próprio sistema, nunca com dado semente."*

---

## Como manter assim

Se algum dado fictício for introduzido — para destravar uma tela antes de a
perna existir, por exemplo — ele **precisa** aparecer aqui com:

1. o que é;
2. onde vive (tabela, arquivo, tela);
3. por que existe;
4. quando sai;
5. como está marcado como fictício na interface.

**Checagem obrigatória antes de qualquer apresentação:** abrir este arquivo. Se
a lista não estiver vazia, cada item precisa estar visualmente marcado na tela.
Um número inventado sem marcação numa demo com cliente é o pior desfecho
possível para este projeto — vale mais mostrar "cobertura insuficiente" (regra 6)
do que um valor plausível.
