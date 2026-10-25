# back2able

Web service that converts Ableton Live 12 `.als` project files to Live 11 format.

## Local development

```sh
bundle install
bundle exec ruby app.rb   # http://localhost:8080
```

## Deployment

The app is deployed as a Docker container to a Hetzner VPS (`one` = 89.167.108.217)
with [Kamal](https://kamal-deploy.org). TLS is terminated by `kamal-proxy`, which
already runs on the box and serves the other apps on that machine.

```sh
./deploy.sh          # build, push to ghcr.io and deploy
./deploy.sh -d ...   # extra flags are passed to `kamal deploy`
```

Notes:

- Kamal builds from the **committed** tree, so commit before deploying.
- `config/deploy.yml` holds the Kamal config (registry, proxy host, builder arch).
- `KAMAL_REGISTRY_PASSWORD` lives in `.kamal/secrets` (gitignored). Reuse the
  GitHub PAT from your other repos.
- The container exposes `8080`; `GET /up` is the healthcheck endpoint used by
  kamal-proxy.
- `RACK_ENV=production` and `PORT=8080` are set by Kamal.

Useful commands:

```sh
kamal logs -f         # tail app logs
kamal app exec -i 'bash' -r web
kamal rollback        # roll back to the previous version
```

### DNS

`back2able.odj.fi` is an A record for `89.167.108.217`, proxied by Cloudflare.
The origin serves HTTPS with a Let's Encrypt certificate issued by kamal-proxy.

### Rollback

Point the DNS record back to the previous host, or redeploy an older image with
`kamal rollback <version>`.
