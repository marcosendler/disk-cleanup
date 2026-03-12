# 🧹 disk-cleanup

Serviço Linux que monitora o uso de disco e apaga automaticamente os arquivos mais antigos de uma pasta quando a partição atinge um limite configurável.

---

## Como funciona

- Roda em segundo plano via **systemd timer** (a cada 15 minutos por padrão)
- Verifica o uso de cada partição configurada
- Se o uso atingir o limite (`threshold_high`), apaga os arquivos mais antigos primeiro
- Para assim que o uso cair abaixo do alvo (`threshold_low`)
- Registra tudo em log com timestamps

---

## Instalação

### Requisitos

- Linux com systemd
- `curl`, `df`, `find`, `numfmt` disponíveis no PATH

### 1 linha

```bash
curl -sSL https://raw.githubusercontent.com/marcosendler/disk-cleanup/master/install.sh -o install.sh
sudo bash install.sh
```

O instalador irá:
1. Verificar as dependências
2. Baixar todos os arquivos do repositório
3. Instalar o script em `/usr/local/bin/`
4. Criar a configuração em `/etc/disk-cleanup.conf`
5. Registrar o timer no systemd e iniciá-lo

> **Nota:** ao rodar via `curl | bash` o instalador opera em modo não-interativo e assume os valores padrão. Para o modo interativo (com confirmações), baixe o script primeiro conforme o exemplo acima.

---

## Configuração

Edite o arquivo de configuração após a instalação:

```bash
sudo nano /etc/disk-cleanup.conf
```

### Estrutura do arquivo

```ini
# Cada partição monitorada é uma seção [nome]
# Você pode adicionar quantas seções quiser

[gravacoes]
target_dir     = /gravacoes           # pasta onde os arquivos serão apagados
mount_point    = /gravacoes           # partição que será monitorada
threshold_high = 95                   # % de uso para iniciar a limpeza
threshold_low  = 80                   # % de uso alvo após a limpeza

[logs]
target_dir     = /var/log
mount_point    = /var/log
threshold_high = 90
threshold_low  = 85
```

### Parâmetros

| Parâmetro        | Descrição                                              |
|------------------|--------------------------------------------------------|
| `target_dir`     | Pasta de onde os arquivos serão apagados               |
| `mount_point`    | Ponto de montagem da partição a ser monitorada         |
| `threshold_high` | Uso (%) que dispara a limpeza                          |
| `threshold_low`  | Uso (%) alvo para encerrar a limpeza                   |

> Para descobrir os pontos de montagem disponíveis no seu sistema, execute `df -h`.

Após editar o arquivo de configuração, não é necessário reiniciar nenhum serviço — o script lê o `.conf` a cada execução.

---

## Gerenciando o serviço

### Ver status do timer

```bash
systemctl status disk-cleanup.timer
```

### Listar próxima execução

```bash
systemctl list-timers disk-cleanup.timer
```

### Executar manualmente (sem esperar o timer)

```bash
sudo systemctl start disk-cleanup.service
```

### Parar o timer temporariamente

```bash
sudo systemctl stop disk-cleanup.timer
```

### Desabilitar (não inicia mais no boot)

```bash
sudo systemctl disable disk-cleanup.timer
```

### Reabilitar

```bash
sudo systemctl enable --now disk-cleanup.timer
```

### Alterar o intervalo de execução

```bash
sudo nano /etc/systemd/system/disk-cleanup.timer
```

Altere a linha `OnUnitActiveSec`:

```ini
OnUnitActiveSec=30min   # a cada 30 minutos
# OnUnitActiveSec=1h    # a cada 1 hora
# OnUnitActiveSec=6h    # a cada 6 horas
```

Após salvar, recarregue:

```bash
sudo systemctl daemon-reload
sudo systemctl restart disk-cleanup.timer
```

---

## Logs

Todos os eventos são registrados em `/var/log/disk-cleanup.log`.

### Acompanhar em tempo real

```bash
tail -f /var/log/disk-cleanup.log
```

### Ver últimas entradas

```bash
tail -50 /var/log/disk-cleanup.log
```

### Ver via journald

```bash
journalctl -u disk-cleanup.service -f
```

### Exemplo de saída

```
[2025-01-10 03:00:00] [global]     Iniciando verificação — lendo /etc/disk-cleanup.conf
[2025-01-10 03:00:00] [gravacoes]  Uso atual em '/': 92%  (limite: 90%, alvo: 85%)
[2025-01-10 03:00:00] [gravacoes]  ALERTA: Uso em 92% — iniciando limpeza em '/var/gravacoes'
[2025-01-10 03:00:01] [gravacoes]  Apagado: /var/gravacoes/rec_20240101_083000.wav (18M)
[2025-01-10 03:00:02] [gravacoes]  Apagado: /var/gravacoes/rec_20240101_091500.wav (24M)
[2025-01-10 03:00:03] [gravacoes]  Uso voltou para 84%. Limpeza concluída.
[2025-01-10 03:00:03] [gravacoes]  Finalizado: 2 arquivo(s) removido(s), 42M liberado(s). Uso final: 84%
[2025-01-10 03:00:03] [backups]    Uso atual em '/mnt/backups': 70%  (limite: 85%, alvo: 80%)
[2025-01-10 03:00:03] [backups]    Dentro do limite. Nada a fazer.
[2025-01-10 03:00:03] [global]     Verificação concluída. 2 partição(ões) processada(s).
```

---

## Desinstalação

```bash
curl -sSL https://raw.githubusercontent.com/marcosendler/disk-cleanup/master/install.sh | sudo bash -s -- --uninstall
```

O desinstalador irá parar e remover o timer, o service e o script. A configuração e o log são opcionais — ele pergunta antes de remover cada um.

---

## Arquivos instalados

| Arquivo                                      | Descrição                        |
|----------------------------------------------|----------------------------------|
| `/usr/local/bin/disk-cleanup.sh`             | Script principal                 |
| `/etc/disk-cleanup.conf`                     | Configuração das partições       |
| `/etc/systemd/system/disk-cleanup.service`   | Unit do systemd                  |
| `/etc/systemd/system/disk-cleanup.timer`     | Timer do systemd                 |
| `/var/log/disk-cleanup.log`                  | Log de execuções                 |
