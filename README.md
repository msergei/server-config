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
