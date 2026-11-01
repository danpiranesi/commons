# Zero-downtime deploy

`bin/deploy` does a blue/green swap: it boots the new release on the free
localhost port (`3000`/`3001`), waits for `/up` (migrations run on boot), then
repoints Caddy at the new port and reloads before stopping the old container. If the new release never turns healthy, Caddy
is never flipped and the old release keeps serving.

The Caddy reload needs root, so the flip runs through a small root-owned helper
(`commons-flip`) that the `deploy` user may run **only** via a scoped `NOPASSWD` sudoers
rule. This keeps deploys hands-off without granting blanket sudo.

## One-time server setup

Run once, from your machine (you'll be prompted for `deploy`'s sudo password):

```bash
# 1. copy the helper up
scp -i ~/.ssh/id_ed25519 deploy/commons-flip deploy@203.0.113.10:/tmp/commons-flip

# 2. install it as root-owned, and add the scoped sudoers rule
ssh -t -i ~/.ssh/id_ed25519 deploy@203.0.113.10 '
  sudo install -o root -g root -m 0755 /tmp/commons-flip /usr/local/bin/commons-flip &&
  rm /tmp/commons-flip &&
  printf "deploy ALL=(root) NOPASSWD: /usr/local/bin/commons-flip 3000 3001, /usr/local/bin/commons-flip 3001 3000\n" | sudo tee /etc/sudoers.d/commons-flip &&
  sudo chmod 0440 /etc/sudoers.d/commons-flip &&
  sudo visudo -c
'
```

`visudo -c` at the end verifies the sudoers file parses; if it reports an error,
remove `/etc/sudoers.d/commons-flip` before logging out.

## Deploying

```bash
bin/deploy
```

## Rollback

The previous release's container is kept (stopped) after each successful deploy,
so rolling back is instant — no rebuild:

```bash
bin/deploy rollback
```

This restarts the previous container, waits for `/up`, flips Caddy back to it,
and stops the current one. (Only the immediately previous release is retained;
to go further back, `git checkout <older-sha> && bin/deploy`.)
