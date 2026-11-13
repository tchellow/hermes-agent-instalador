# Instalador do Hermes Agent para Ubuntu

Um script que instala o [Hermes Agent](https://github.com/NousResearch/hermes-agent) num container Docker isolado e o conecta a um modelo **DeepSeek pelo OpenRouter** e a um **bot próprio no Telegram**.

```bash
git clone https://github.com/tchellow/hermes-agent-instalador.git
cd hermes-agent-instalador
./instalar-hermes.sh
```

## O que o script faz

1. Confere o sistema: Ubuntu, 64 bits, espaço em disco e `sudo`.
2. Instala o **Docker Engine** e o **Docker Compose** pelo [repositório oficial da Docker](https://docs.docker.com/engine/install/ubuntu/), se ainda não estiverem instalados.
3. Baixa o código oficial do Hermes e fixa a **última versão estável**, ignorando as versões `rc` e `canary`.
4. Cria `~/hermes/docker-compose.yml` e `~/hermes/.env`, e monta a imagem.
5. Pede a **chave do OpenRouter** e confere se ela funciona.
6. Pede o **token do bot** e o **seu ID do Telegram**, e confere o token.
7. Grava a configuração, liga o Hermes e espera o Telegram conectar.

Pode rodar o script de novo sem medo: ele reaproveita o que já existe e pergunta antes de trocar chaves.

## Requisitos

| Item | Mínimo |
| --- | --- |
| Sistema | Ubuntu 24.04 ou 26.04 LTS, 64 bits (x86_64 ou arm64) |
| Memória | 8 GB de RAM |
| Disco | 15 GB livres (a imagem ocupa uns 5 GB) |
| Conta | [OpenRouter](https://openrouter.ai) com créditos |
| Telegram | Instalado no celular |

## Antes de rodar

**Chave do OpenRouter**

1. Crie a conta em [openrouter.ai](https://openrouter.ai) e adicione créditos.
2. Em [openrouter.ai/keys](https://openrouter.ai/keys), crie uma chave só para o Hermes, com **limite de crédito**.
3. Copie a chave (começa com `sk-or-`). Ela aparece uma vez só.

**Bot do Telegram**

1. Fale com o [@BotFather](https://t.me/BotFather), mande `/newbot` e copie o token.
2. Fale com o [@userinfobot](https://t.me/userinfobot) para descobrir o seu ID numérico.

Use um bot **novo**. Um bot que outro programa já usa entra em conflito e para de receber mensagens.

## Uso

```bash
./instalar-hermes.sh                 # instalação completa
./instalar-hermes.sh --dashboard     # também liga o painel web
./instalar-hermes.sh --sem-telegram  # sem bot (só terminal)
```

| Opção | O que faz |
| --- | --- |
| `--sem-telegram` | Não configura o Telegram. Dá para configurar depois rodando o script de novo. |
| `--dashboard` | Liga o painel web em `http://localhost:9119`, com login. |
| `--nao-iniciar` | Instala e configura, mas não liga o Hermes. |
| `--sem-validar` | Não confere a chave e o token online (útil sem internet estável). |
| `-h`, `--help` | Mostra a ajuda. |

Variáveis de ambiente opcionais:

| Variável | Padrão | Para quê |
| --- | --- | --- |
| `HERMES_DIR` | `~/hermes` | Pasta da instalação |
| `HERMES_VERSION` | última estável | Fixar uma versão, ex. `v0.23.1` |
| `HERMES_MODEL` | `deepseek/deepseek-v4.1-flash` | Modelo no OpenRouter |
| `HERMES_MEM_LIMIT` | `2g` | Limite de memória do container |
| `HERMES_CPUS` | `2` | Limite de CPUs do container |

Exemplo: `HERMES_MODEL=deepseek/deepseek-v4-pro ./instalar-hermes.sh`

### Modelos DeepSeek sugeridos

| Modelo | Entrada / saída (US$ por milhão de tokens) | Quando usar |
| --- | --- | --- |
| `deepseek/deepseek-v4.1-flash` | 0,30 / 1,20 | Padrão: rápido e barato |
| `deepseek/deepseek-v4-pro` | 0,90 / 1,50 | Tarefas difíceis, com vários passos |

Preços do OpenRouter em 13/11/2026. Confira os atuais em [openrouter.ai/deepseek](https://openrouter.ai/deepseek). Cada mensagem envia cerca de 19 mil tokens de instruções do agente, além do seu texto.

## Depois da instalação

Todos os comandos rodam dentro de `~/hermes`:

| Para | Comando |
| --- | --- |
| Ver se está no ar | `docker compose ps` |
| Acompanhar o log | `tail -f data/logs/gateway.log` |
| Reiniciar | `docker compose restart gateway` |
| Desligar | `docker compose down` |
| Ligar | `docker compose up -d` |
| Conversar pelo terminal | `docker compose exec -it gateway hermes` |
| Senha do painel web | `grep DASHBOARD_PASSWORD .env` |

O log útil fica em `data/logs/gateway.log`; o `docker compose logs` mostra pouco. O Hermes liga sozinho quando o computador reinicia.

Se o script instalou o Docker agora, **saia da sessão e entre de novo** para usar `docker` sem `sudo`.

### Trocar o modelo

```bash
cd ~/hermes
docker compose exec -T gateway hermes config set model.default deepseek/deepseek-v4-pro
docker compose restart gateway
```

### Atualizar o Hermes

Rode o script de novo. Ele baixa a última versão estável, monta a imagem nova e mantém configuração, memória e Telegram. Para voltar à versão anterior, ajuste `HERMES_VERSION` em `~/hermes/.env` e rode `docker compose up -d`.

## Como fica instalado

```
~/hermes/
├── docker-compose.yml   # container isolado, gerado pelo script
├── .env                 # versão, limites e senha do painel (permissão 600)
├── src/                 # código oficial do Hermes, na versão fixada
└── data/                # configuração, memória, logs e chaves (.env, permissão 600)
```

O container:

- tem **rede própria** e **não** usa `network_mode: host`;
- **não** acessa o Docker do computador (sem `/var/run/docker.sock`);
- tem limite de memória e CPU;
- só faz **conexões de saída**, para o OpenRouter e o Telegram. Nenhuma porta fica aberta para a internet;
- deixa o painel web, quando ligado, só em `127.0.0.1`.

## Segurança

- O script lê chave e token **sem mostrá-los na tela** e sem gravá-los no histórico do terminal.
- Nunca compartilhe `~/hermes/.env`, a pasta `~/hermes/data` ou prints com chaves.
- Deixe **só o seu ID** em `TELEGRAM_ALLOWED_USERS`. Quem estiver liberado consegue mandar o agente executar comandos.
- Defina **limite de crédito** na chave do OpenRouter.
- Para abrir o painel para outros computadores da rede, troque `DASHBOARD_BIND` no `.env` pelo IP do computador. A conexão é HTTP sem criptografia: faça isso só em rede de confiança, nunca na internet.

Se uma chave vazar:

| O que vazou | O que fazer |
| --- | --- |
| Chave do OpenRouter | Revogue em [openrouter.ai/keys](https://openrouter.ai/keys) e rode o script de novo |
| Token do Telegram | No @BotFather, `/revoke`, e rode o script de novo |
| Senha do painel | Troque `DASHBOARD_PASSWORD` no `.env` e rode `docker compose --profile dashboard up -d` |

## Problemas comuns

| Sintoma | Solução |
| --- | --- |
| `permission denied` ao usar `docker` | Saia da sessão e entre de novo (grupo `docker` recém-adicionado) |
| Bot não responde | `docker compose restart gateway` e confira `grep -i telegram data/logs/gateway.log \| tail` |
| Primeira mensagem sem resposta | Mensagens enviadas com o Hermes desligado são descartadas; mande de novo |
| Bot parou depois de mudar a configuração | O `hermes gateway setup` desliga o gateway: `docker compose restart gateway` |
| Erro 401 ou 402 no log | Chave do OpenRouter errada ou sem crédito |
| Build falha | Confira o espaço em disco (`df -h`) e a internet; rode o script de novo |

## Desinstalar

```bash
cd ~/hermes
docker compose --profile dashboard down
docker image rm "hermes-agent:$(grep ^HERMES_VERSION .env | cut -d= -f2)"
rm -rf ~/hermes   # apaga configuração, memória e chaves
```

## Créditos

O [Hermes Agent](https://github.com/NousResearch/hermes-agent) é um projeto da Nous Research. Este repositório contém só o script de instalação e não tem ligação com a Nous Research.

## Licença

[MIT](LICENSE). O Hermes Agent, baixado pelo script, tem a licença própria do projeto original.
