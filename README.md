# server-config
Apply server configuration via Terraform

## Disk usage

The configuration installs `top-dirs` in `/usr/local/bin`:

```bash
sudo top-dirs
sudo top-dirs -n 20 -x /home/jr/share /
```

The scan stays on the filesystem containing the selected root path. Use
`--exclude` multiple times to omit large directories that would distort the
result.

## Docker cleanup

The weekly `docker-prune.timer` removes stopped containers, images unused by
any remaining container, and build cache older than seven days. It never
prunes Docker volumes.

## Time sync

The configuration installs and enables `chrony` on the host via
`scripts/setup-time-sync`. It uses Debian, German, and European NTP pools,
enables RTC sync, and allows an initial clock step so services with strict
replay protection do not run with a stale clock.

For an already configured server, copy and run the script as root:

```bash
scp scripts/setup-time-sync jr@SERVER:/tmp/setup-time-sync
ssh jr@SERVER 'sudo install -m 755 /tmp/setup-time-sync /usr/local/bin/setup-time-sync && sudo /usr/local/bin/setup-time-sync'
```

If the server is managed by this Terraform state, apply only the time-sync
resource:

```bash
terraform apply -target=null_resource.time_sync
```
