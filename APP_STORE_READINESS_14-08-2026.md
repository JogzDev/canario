# App Store readiness — 14/08/2026

Este é um portão de submissão, não uma lista de desejos. “Verde” significa que
o binário ou a configuração já foi verificado; “bloqueador” significa que não
devemos enviar para revisão enquanto estiver aberto.

## Estado executivo

**Ainda não está pronto para submissão.** O código, o nome DataDrobe e o idioma
inglês estão prontos para um build interno, mas há bloqueadores de backend,
assinatura de distribuição e metadata. A ordem mais curta para chegar ao
TestFlight é:

1. implantar e validar a análise visual A15, ou mantê-la desligada e assumir
   publicamente que a v1 só tem formulário manual;
2. resolver a permissão do perfil App Store e exportar o Archive já gerado;
4. publicar Privacy Policy e Support URL;
5. preencher App Privacy e toda a ficha do App Store Connect;
6. passar uma rodada física no iPhone e distribuir por TestFlight antes da
   revisão externa.

## Verde no código

| Item | Estado | Evidência |
|---|---|---|
| SDK aceito | ✅ | Xcode 26.2 / iOS SDK 26.2; atende ao mínimo vigente de iOS 26 SDK |
| Plataforma | ✅ | iPhone only, portrait, deployment target iOS 17 |
| Builds Debug e Release | ✅ | 143 testes Swift e build completo para simulador verdes; Archive Release gerado em 14/08 |
| Ícone | ✅ | AppIcon universal 1024 px no asset catalog |
| Criptografia | ✅ | somente HTTPS; `ITSAppUsesNonExemptEncryption=false` |
| Permissões | ✅ | câmera e fototeca possuem purpose strings em inglês |
| Privacidade técnica | ✅ parcial | manifesto válido, sem tracking; foto declarada para App Functionality no desenho A15 |
| Acessibilidade estrutural | ✅ parcial | Dynamic Type e componentes nativos; revisão física ainda necessária |
| Nome e idioma | ✅ | nome exibido DataDrobe, versão 1.0 (1), interface principal padronizada em inglês; ids históricos continuam estáveis |
| Recorte local | ✅ | Vision isola a peça no aparelho, pixels transparentes não entram na cor e o usuário pode reposicionar/zoomar |
| Pipeline | 🟡 | diagnóstico de zero VTEX corrigido e testado; precisa observar uma execução remota após a publicação |

## Bloqueadores antes do upload

### B1 — decisão de escopo da análise visual

A leitura remota está implementada atrás de um interruptor. A Edge Function foi
implantada, mas precisa dos secrets, da migração de limite e de um teste real
antes de virar
`REMOTE_ANALYSIS_ENABLED=YES`. Sem isso, a alternativa honesta é enviar a v1
com o formulário manual e sem prometer reconhecimento visual.

Critério de fechamento:

- função implantada e limite de custo ativo;
- consentimento visível antes de cada envio;
- fallback manual funcionando sem rede;
- categoria e cor conferidas no device;
- App Privacy do App Store Connect declara Photos or Videos, not linked,
  App Functionality;
- screenshots e descrição não prometem medir composição ou dimensões invisíveis.

### B2 — assinatura Release

O Archive Release foi gerado, mas usou assinatura de desenvolvimento. A
exportação App Store falhou porque a conta atual não tem permissão para criar o
provisioning profile de distribuição de `com.canario.app`.

Critério de fechamento:

- Team ID único e correto;
- bundle id `com.canario.app` registrado ou substituído pelo definitivo;
- versão e build definidos;
- Account Holder/Admin cria o perfil App Store ou concede acesso a
  Certificates, Identifiers & Profiles;
- archive exportado com distribuição, sem `get-task-allow`;
- upload e processamento do build no App Store Connect.

### B3 — URLs e metadata obrigatória

Faltam evidências de URLs públicas de Privacy Policy e Support, além da ficha
do App Store Connect. O texto dentro do app ajuda, mas não substitui a URL de
Privacy Policy exigida na metadata.

Critério de fechamento:

- Privacy Policy URL e Support URL públicas;
- descrição, subtítulo, keywords, categoria e copyright;
- age rating e conteúdo de terceiros;
- App Privacy coerente com OpenAI, Supabase e hotlinks das lojas;
- screenshots reais, sem placeholders, para os tamanhos exigidos;
- Review Notes explicando conta inexistente, dados de demonstração e acesso às
  funções que dependem do backend.

### B4 — conteúdo e links de terceiros

Imagens e páginas das lojas são carregadas por hotlink. A auditoria testou 262
destinos: 183 sem sinal técnico de problema. Foram encontrados links mortos,
produto esgotado e o domínio administrativo da Maria Filó; a correção P7 troca
o domínio e exclui candidatos antigos/esgotados da resposta, mas ainda precisa
ser aplicada e observada. Os termos/licenças das lojas continuam sendo uma
decisão jurídica do grupo.

### B5 — backend operacional

A revisão da Apple pode abrir o app dias depois do upload. Pipeline, Supabase e
Edge Function precisam continuar disponíveis, com telas de falha honestas.
Depois da limpeza segura, o banco mede **467.963.027 bytes (446,28 MiB), 93,59%
do limite decimal de 500 MB**, com 32.036.973 bytes de margem. Foram recuperados
aproximadamente 16,8 MB em tabelas temporárias vazias; não há outra exclusão
segura relevante sem sacrificar história. O portão operacional permanece em
96%, portanto ainda exige acompanhamento antes da revisão.

## Checklist de TestFlight

- [ ] Pipeline diário verde após a correção VTEX.
- [ ] Análise Luna implantada/ativada ou removida das promessas da v1.
- [x] Navegação principal em inglês.
- [x] Nome DataDrobe, version 1.0 e build 1.
- [ ] Archive Release assinado.
- [ ] Privacy report do archive revisado.
- [ ] App Privacy e URLs públicas preenchidas.
- [ ] Cold launch, câmera, fototeca, modo offline e exclusão do Closet no device.
- [ ] VoiceOver, Dynamic Type, Dark Mode e Reduce Motion.
- [ ] Links e imagens de similares/eventos por marca.
- [ ] TestFlight interno com JP, Davi e Bianca; bugs P0/P1 zerados.
