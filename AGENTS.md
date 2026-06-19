# AGENTS.md

Guia para agentes que trabajen en este repositorio.

## Contexto del proyecto

Este repositorio contiene `carbonio-mailops`, un utilitario Bash operacional para Carbonio CE/Zimbra. Se usa en servidores reales para:

- migraciones
- backup full
- backup incremental
- export/import de buzones
- export/import de cuentas, aliases, listas de distribucion, firmas y reglas
- recuperacion de backups parciales
- reportes de peso, estado y actividad de buzones

El servidor operativo principal observado usa Carbonio con usuario `zextras`, rutas tipo `/opt/zextras/bin` y despliegue bajo `/opt/carbonio-tools`.

## Reglas criticas

- No abrir ni imprimir `.varset` salvo que el usuario lo pida explicitamente. Puede contener credenciales.
- No borrar `backup_*`, `log/` ni archivos no trackeados sin confirmacion explicita.
- No usar `git reset --hard` ni limpiezas destructivas para resolver pulls en servidor.
- Si el usuario quiere traer cambios remotos y conservar backups/logs, usar `git restore` solo sobre archivos trackeados o `git stash`; no tocar `??`.
- Mantener compatibilidad con `mail_migrate.sh`; actualmente es wrapper hacia `carbonio-mailops.sh`.
- En operaciones reales, preferir comandos que no regeneren TGZ grandes si ya existen.

## Arquitectura

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
```

## CLI

Los comandos se definen en `lib/cli.sh` dentro de `command_specs` con el formato:

```text
grupo|comando|descripcion|handler
```

Al agregar un comando:

1. Crear la funcion operacional en el modulo correspondiente.
2. Crear `run_*` en `lib/cli.sh`.
3. Agregar una linea en `command_specs`.
4. Validar `--help`.

## Comportamiento esperado de export

`--export` es full global:

- cuentas
- passwords
- userdata
- distribution lists
- aliases
- TGZ de buzones
- firmas
- reglas
- transferencia si esta habilitada

`--export-mailbox-list <file>` debe ser full acotado a la lista, no solo TGZ.

`--complete-mailbox-list-backup <backup_dir> <file>` completa un backup existente sin regenerar TGZ no vacios.

`export_mailbox` debe saltar TGZ existentes no vacios:

```text
Skipping existing mailbox backup: ...
```

## Errores criticos vs no criticos

Criticos, deben abortar:

- `.varset` faltante
- usuario incorrecto
- no detectar Carbonio/Zimbra
- lista de buzones inexistente
- lista sin buzones validos
- fallo exportando TGZ de buzon

No criticos, deben continuar con `log_warn`:

- distribution list listada por `gadl` pero fallida en `gdlm`
- alias no exportable
- firma inexistente/no exportable
- reglas inexistentes/no exportables
- calendario/contactos no exportables
- password hash o userdata no exportable para una cuenta puntual

No convertir condiciones esperadas de "no hay datos" en error fatal bajo `set -Eeuo pipefail`.

## Carbonio/Zimbra wrappers

Usar siempre wrappers:

```bash
prov ...
mailbox ...
control ...
localconfig ...
```

No llamar directamente `zmprov`, `zmmailbox`, `zmcontrol` o `zmlocalconfig` salvo en texto de log/documentacion.

## Listas de buzones

Las listas en `mailbox_groups/` deben preservar exactamente los correos dados por el usuario. No corregir ortografia, nombres, dominios ni transliterar.

Leccion aprendida: cambiar `rosmery` a `rosemary` o `villareal` a `villarreal` rompe backups reales.

Si se debe balancear por peso:

- ordenar por peso descendente
- asignar cada buzon al grupo con menor GB acumulado
- documentar peso aproximado, cantidad de buzones e hilos sugeridos

Para este caso se uso:

```text
N_PROC_PARALLEL=2
~188 GB por tanda
~7.5 h por tanda con eficiencia conservadora del 70%
```

## Validacion

Ejecutar antes de responder como completado:

```bash
bash -n carbonio-mailops.sh mail_migrate.sh functions.sh lib/*.sh
git diff --check
./carbonio-mailops.sh --help
```

Si se toca `mailbox_groups/`, validar:

```bash
wc -l mailbox_groups/tanda_*.txt
sort mailbox_groups/tanda_*.txt | uniq -d
```

## Operacion en servidor

Para completar un backup parcial sin rehacer TGZ:

```bash
./carbonio-mailops.sh --complete-mailbox-list-backup backup_full_YYYYMMDDHHMMSS mailbox_groups/tanda_XX_8h_2hilos.txt
```

Para una tanda nueva:

```bash
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_XX_8h_2hilos.txt
```

Para pull en servidor con backups/logs no trackeados:

```bash
git status --short
git restore <archivos-trackeados-a-descartar>
git pull --ff-only
```

Los `?? backup_*` y `?? log/` se mantienen si solo se usa `git restore` sobre archivos trackeados.

## Estilo

- Bash estricto: `set -Eeuo pipefail`.
- Citar rutas y variables.
- Preferir `while read -r` para listas.
- Usar `awk` cuando `grep` pueda devolver 1 por "sin resultados" esperado.
- No agregar dependencias externas innecesarias.
- Mantener logs operativos claros: `begin_process`, `end_process`, `log_info`, `log_warn`, `log_error`.
