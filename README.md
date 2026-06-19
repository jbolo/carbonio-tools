# Carbonio MailOps

Utilitario Bash operacional para Carbonio CE/Zimbra orientado a migraciones, backups full/incrementales, export/import de buzones y recuperacion de respaldos parciales.

El entrypoint principal es:

```bash
./carbonio-mailops.sh <command> [args]
```

`mail_migrate.sh` se mantiene como wrapper compatible para ejecuciones antiguas.

## Requisitos

- Ejecutar como el usuario de la plataforma (`zextras` en Carbonio o `zimbra` en Zimbra).
- Tener `.varset` en la raiz del proyecto.
- Tener disponibles los binarios configurados en `.varset`, normalmente:
  - `/opt/zextras/bin/carbonio`
  - `/opt/zextras/bin/zmmailbox`
  - `/opt/zextras/bin/zmcontrol`
  - `/opt/zextras/bin/zmlocalconfig`

No versionar `.varset`, logs ni directorios `backup_*`, porque pueden contener secretos, hashes, datos de usuarios y respaldos reales.

## Comandos

Ver ayuda:

```bash
./carbonio-mailops.sh --help
```

Export full completo:

```bash
./carbonio-mailops.sh --export
```

Export incremental:

```bash
./carbonio-mailops.sh --export-incremental
```

Export de un solo buzon:

```bash
./carbonio-mailops.sh --export-mailbox-user usuario@dominio.com
```

Export completo acotado a una lista de buzones:

```bash
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_01_8h_2hilos.txt
```

Completar un backup ya existente sin regenerar TGZ existentes:

```bash
./carbonio-mailops.sh --complete-mailbox-list-backup backup_full_YYYYMMDDHHMMSS mailbox_groups/tanda_01_8h_2hilos.txt
```

Import full:

```bash
./carbonio-mailops.sh --import
```

Import mailbox:

```bash
./carbonio-mailops.sh --import-mailbox
```

Estado y reporte:

```bash
./carbonio-mailops.sh --status
```

## Backups por tandas

Para ventanas nocturnas limitadas, usar `--export-mailbox-list` con listas en `mailbox_groups/`.

Las listas actuales estan balanceadas para una ventana aproximada de 8 horas con:

```bash
N_PROC_PARALLEL=2
```

Archivos:

```text
mailbox_groups/tanda_01_8h_2hilos.txt
mailbox_groups/tanda_02_8h_2hilos.txt
mailbox_groups/tanda_03_8h_2hilos.txt
mailbox_groups/tanda_04_8h_2hilos.txt
```

La estrategia usada fue balancear por peso total aproximado, no por cantidad de buzones. Cada tanda pesa cerca de 188 GB.

## Estructura generada por backup

Un backup full puede contener:

```text
backup_full_YYYYMMDDHHMMSS/
  accounts_YYYYMMDDHHMMSS.txt
  domains_YYYYMMDDHHMMSS.txt
  emails_YYYYMMDDHHMMSS.txt
  report_YYYYMMDDHHMMSS.txt
  mailbox_YYYYMMDDHHMMSS/
  userpass_YYYYMMDDHHMMSS/
  userdata_YYYYMMDDHHMMSS/
  dlist_YYYYMMDDHHMMSS/
  alias_YYYYMMDDHHMMSS/
  user_signature_YYYYMMDDHHMMSS/
  rules_YYYYMMDDHHMMSS/
```

`--export-mailbox-list` ahora genera un export completo acotado a la lista:

- datos de cuenta
- password hash si esta disponible
- listas de distribucion
- TGZ de buzon
- aliases
- firmas
- reglas
- reporte operativo

Si el backup ya tiene TGZ no vacios, el script los salta para evitar regenerar respaldos pesados.

## Recuperar un backup parcial

Si una tanda genero TGZ pero fallo en metadatos, completar sin rehacer buzon:

```bash
./carbonio-mailops.sh --complete-mailbox-list-backup backup_full_20260616234501 mailbox_groups/tanda_01_8h_2hilos.txt
```

El comando reutiliza el backup existente, reconstruye contexto por fecha y completa carpetas faltantes. Los TGZ existentes se reportan como:

```text
Skipping existing mailbox backup: ...
```

## Backup offsite con Restic y Cloudflare R2

Los scripts en `scripts/` permiten ejecutar export Carbonio y luego subir snapshots Restic a un bucket S3-compatible como Cloudflare R2.

No guardar credenciales en el repositorio. Crear el archivo de entorno fuera de Git, por ejemplo como usuario `zextras`:

```bash
mkdir -p ~/.config/restic
chmod 700 ~/.config/restic
nano ~/.config/restic/r2.env
chmod 600 ~/.config/restic/r2.env
```

Contenido esperado:

```bash
export RESTIC_REPOSITORY="s3:https://<ACCOUNT_ID>.r2.cloudflarestorage.com/<BUCKET>"
export AWS_ACCESS_KEY_ID="<R2_ACCESS_KEY_ID>"
export AWS_SECRET_ACCESS_KEY="<R2_SECRET_ACCESS_KEY>"
export RESTIC_PASSWORD="<CLAVE_LARGA_RESTIC>"
export RESTIC_COMPRESSION=max
```

Inicializar el repositorio una sola vez:

```bash
source ~/.config/restic/r2.env
restic init
```

Ejecutar full manual:

```bash
./scripts/backup-full-r2.sh
```

Ejecutar incremental manual:

```bash
./scripts/backup-incremental-r2.sh
```

Los logs quedan en:

```text
log/restic_full_YYYY-MM-DD_HHMMSS.log
log/restic_incremental_YYYY-MM-DD_HHMMSS.log
```

Cron sugerido como usuario `zextras`:

```cron
# Full semanal domingo 01:00
0 1 * * 0 /opt/carbonio-tools/scripts/backup-full-r2.sh

# Incremental lunes a sabado 02:00
0 2 * * 1-6 /opt/carbonio-tools/scripts/backup-incremental-r2.sh
```

Los scripts usan lock files en `/tmp` para evitar ejecuciones simultaneas.

Para correr una verificacion Restic despues de cada backup:

```bash
RESTIC_RUN_CHECK=1 ./scripts/backup-full-r2.sh
```

Retencion sugerida:

```bash
source ~/.config/restic/r2.env
restic forget --tag carbonio --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
```

Antes de borrar backups locales, confirmar que existe snapshot remoto:

```bash
source ~/.config/restic/r2.env
restic snapshots --tag carbonio
restic check
```

## Criterios de error

Errores criticos que deben abortar:

- no existe `.varset`
- usuario incorrecto
- no se identifica Carbonio/Zimbra
- archivo de lista inexistente
- cero buzones validos en una lista
- fallo al exportar TGZ de buzon

Errores no criticos que deben continuar con warning:

- lista de distribucion inconsistente (`gadl` la lista, `gdlm` falla)
- alias no exportable para una cuenta
- firma inexistente o no exportable
- reglas inexistentes o no exportables
- calendario/contactos no exportables
- password hash o userdata no exportable de una cuenta puntual

## Modulos

```text
carbonio-mailops.sh      Entry point principal
mail_migrate.sh          Wrapper compatible
functions.sh             Wrapper compatible hacia lib/logging.sh
lib/cli.sh               Tabla de comandos, usage y dispatch
lib/context.sh           Deteccion de entorno, rutas y listas de cuentas
lib/carbonio.sh          Wrappers prov/mailbox/control/localconfig
lib/export.sh            Exportaciones y recuperacion de backups parciales
lib/import.sh            Importaciones
lib/report.sh            Reporte operativo de buzones/cuentas
lib/backup.sh            Limpieza de backups antiguos
lib/transfer.sh          Transferencia por rsync
lib/logging.sh           Logging, traps, notificaciones y jobs
mailbox_groups/          Tandas operativas por peso
scripts/                 Wrappers operativos para Restic/R2
```

## Validacion local

Antes de subir cambios:

```bash
bash -n carbonio-mailops.sh mail_migrate.sh functions.sh lib/*.sh
git diff --check
./carbonio-mailops.sh --help
```

No ejecutar comandos reales contra Carbonio/Zimbra durante desarrollo local salvo que se este operando en el servidor correcto y con ventana aprobada.
