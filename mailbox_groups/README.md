# Mailbox Backup Groups

Grupos balanceados para ejecutar backups full por tandas con una ventana aproximada de 8 horas.

Estimacion usada:
- Total aproximado: 752.6 GB
- Referencia observada: 6 GB en 20 min por hilo
- Velocidad base: 18 GB/h por hilo
- Con 2 hilos y eficiencia conservadora del 70%: ~25.2 GB/h
- Cada tanda: ~188 GB, estimado ~7.5 horas

Usar `N_PROC_PARALLEL=2` en `.varset` para estas tandas.

Comandos sugeridos:

```bash
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_01_8h_2hilos.txt
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_02_8h_2hilos.txt
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_03_8h_2hilos.txt
./carbonio-mailops.sh --export-mailbox-list mailbox_groups/tanda_04_8h_2hilos.txt
```

Resumen:

```text
tanda_01_8h_2hilos.txt  45 buzones  ~188.14 GB  2 hilos
tanda_02_8h_2hilos.txt  46 buzones  ~188.14 GB  2 hilos
tanda_03_8h_2hilos.txt  57 buzones  ~188.14 GB  2 hilos
tanda_04_8h_2hilos.txt  49 buzones  ~188.14 GB  2 hilos
```
