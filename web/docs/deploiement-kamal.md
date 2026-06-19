# Deployer Sillage avec Kamal

Ce guide part de l'etat actuel de l'application : Rails 8, Ruby 4.0.3,
SQLite en production, Active Storage local, Solid Queue et Kamal 2.

L'objectif est un deploiement simple sur un VPS unique a l'adresse
`sillage.wild.eu`, avec Docker, HTTPS via kamal-proxy, donnees persistantes dans
`/rails/storage`, et jobs Solid Queue executes dans Puma.

## 1. Preparer le serveur

Il faut un VPS Linux avec :

- Ubuntu/Debian recent.
- Le nom de domaine `sillage.wild.eu` qui pointe vers l'IP du serveur.
- Les ports `22`, `80` et `443` ouverts.
- Un acces SSH fonctionnel, idealement avec une cle :

```sh
ssh root@sillage.wild.eu
```

Kamal peut installer Docker pendant `kamal setup`, mais le compte SSH doit
avoir les droits necessaires. Le cas le plus simple pour un premier deploy est
`root`.

## 2. Verifier Kamal en local

Kamal est deja disponible sur cette machine :

```sh
kamal version
```

Si tu dois l'installer ailleurs :

```sh
gem install kamal
```

## 3. Dockerfile de production

Le repo contient maintenant ce `Dockerfile` a la racine :

```dockerfile
# syntax=docker/dockerfile:1
# check=error=true

ARG RUBY_VERSION=4.0.3
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

WORKDIR /rails

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y curl libjemalloc2 libvips sqlite3 && \
    ln -s /usr/lib/$(uname -m)-linux-gnu/libjemalloc.so.2 /usr/local/lib/libjemalloc.so && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_JOBS="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_RETRY="3" \
    BUNDLE_WITHOUT="development" \
    LD_PRELOAD="/usr/local/lib/libjemalloc.so"

FROM base AS build

RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y build-essential git libsqlite3-dev libvips libyaml-dev pkg-config && \
    rm -rf /var/lib/apt/lists /var/cache/apt/archives

COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile -j 1 --gemfile

COPY . .

RUN bundle exec bootsnap precompile -j 1 app/ lib/
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

FROM base

RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash

USER 1000:1000

COPY --chown=rails:rails --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --chown=rails:rails --from=build /rails /rails

ENTRYPOINT ["/rails/bin/docker-entrypoint"]

EXPOSE 3000
CMD ["./bin/rails", "server"]
```

Ajoute aussi `bin/docker-entrypoint` :

```sh
#!/bin/bash -e

if [ "${@: -2:1}" == "./bin/rails" ] && [ "${@: -1:1}" == "server" ]; then
  ./bin/rails db:prepare
fi

exec "${@}"
```

Puis rends-le executable :

```sh
chmod +x bin/docker-entrypoint
```

Ajoute enfin `.dockerignore` :

```dockerignore
/.git
/.github
/.kamal
/log/*
/tmp/*
!/tmp/.keep
!/tmp/pids
/storage/*
!/storage/.keep
/public/assets
/vendor/bundle
/.env*
/config/master.key
.DS_Store
```

## 4. Fichiers Kamal

La configuration concrete est deja en place :

- `config/deploy.yml`
- `.kamal/secrets.example`
- `.kamal/hooks/pre-build`
- `Dockerfile`
- `.dockerignore`
- `bin/docker-entrypoint`

## 5. Configurer `config/deploy.yml`

Exemple pour un VPS unique :

```yaml
service: sillage
image: sillage

servers:
  web:
    - sillage.wild.eu

proxy:
  ssl: true
  host: sillage.wild.eu
  app_port: 3000
  forward_headers: true

registry:
  server: 127.0.0.1:5555
  username: registry
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    SOLID_QUEUE_IN_PUMA: true
    RAILS_LOG_LEVEL: info
  secret:
    - RAILS_MASTER_KEY
    - CESIUM_ION_TOKEN

volumes:
  - "sillage_storage:/rails/storage"

asset_path: /rails/public/assets

builder:
  arch: amd64
  remote: ssh://root@sillage.wild.eu
  local: false

aliases:
  console: app exec --interactive --reuse "bin/rails console"
  shell: app exec --interactive --reuse "bash"
  logs: app logs -f
  dbc: app exec --interactive --reuse "bin/rails dbconsole --include-password"
```

Cette config utilise un registry prive sur le VPS (`127.0.0.1:5555`) et un
builder Docker distant sur ce meme VPS. Elle ne demande pas de compte Docker Hub
ou GHCR pour demarrer, et elle evite le tunnel de registry local Kamal.

Le hook `.kamal/hooks/pre-build` force ce builder distant en `network=host`.
C'est necessaire pour que BuildKit puisse pousser l'image vers la registry privee
liee a `127.0.0.1:5555` sur le VPS.

## 6. Configurer l'env local

Copie l'exemple vers le fichier local ignore par Git :

```sh
cp .env.deploy.local.example .env.deploy.local
```

Dans `.env.deploy.local`, mets les valeurs locales :

```sh
RAILS_MASTER_KEY=
KAMAL_REGISTRY_PASSWORD=registry
CESIUM_ION_TOKEN=
```

Ce fichier local peut contenir des vraies valeurs. Il est ignore par Git.
`CESIUM_ION_TOKEN` est optionnel : laisse-le vide si tu n'en as pas.

`.kamal/secrets` reste seulement un pont Kamal vers ces variables :

```sh
cp .kamal/secrets.example .kamal/secrets
```

## 7. Configurer Rails pour le domaine

Dans `config/environments/production.rb`, ajoute ton domaine a `config.hosts` :

```ruby
config.hosts = [
  "sillage.wild.eu"
]
```

La config actuelle a deja `config.assume_ssl = true` et
`config.force_ssl = true`, ce qui est coherent avec `proxy.ssl: true`.

## 8. Premier deploy

Commit les changements avant de lancer Kamal, car le build Kamal utilise le hash
Git courant :

```sh
git status
git add Dockerfile .dockerignore bin/docker-entrypoint config/deploy.yml .kamal/secrets.example .env.deploy.local.example Gemfile Gemfile.lock config/database.yml config/environments/production.rb docs/deploiement-kamal.md
git commit -m "Add Kamal deployment config"
```

Lance ensuite :

```sh
kamal setup
```

Au premier passage, Kamal va se connecter en SSH, installer Docker si besoin,
se connecter au registre, construire l'image, la pousser, lancer kamal-proxy,
demarrer le conteneur Rails, attendre que `/up` reponde, puis router le trafic.

Les deploys suivants se font avec :

```sh
kamal deploy
```

## 9. Commandes utiles

Voir l'etat :

```sh
kamal details
```

Suivre les logs :

```sh
kamal app logs -f
```

Ouvrir une console Rails :

```sh
kamal app exec --interactive --reuse "bin/rails console"
```

Ouvrir un shell dans le conteneur :

```sh
kamal app exec --interactive --reuse "bash"
```

Redemarrer l'app sans rebuild :

```sh
kamal app boot
```

Rollback :

```sh
kamal rollback VERSION
```

La liste des versions apparait dans `kamal details`.

## 10. Backups SQLite et Active Storage

Cette app stocke la base SQLite et les uploads Active Storage dans
`/rails/storage`, monte via le volume Docker `sillage_storage`.

Ce volume doit etre sauvegarde. Exemple manuel sur le serveur :

```sh
docker run --rm \
  -v sillage_storage:/data \
  -v "$PWD:/backup" \
  alpine \
  tar czf /backup/sillage-storage-$(date +%Y%m%d-%H%M%S).tgz -C /data .
```

Pour restaurer, stoppe l'app avant de remplacer le contenu du volume.

## 11. Pieges classiques

- DNS pas encore propage : Let's Encrypt echouera si `sillage.wild.eu` ne pointe
  pas vers le serveur.
- Port 80 ou 443 ferme : kamal-proxy ne pourra pas servir HTTP/HTTPS.
- Registry local Kamal inaccessible : verifie que le serveur accepte SSH et que
  Docker peut etre installe/lance.
- `RAILS_MASTER_KEY` absent : Rails ne pourra pas lire les credentials.
- Volume absent ou mal monte : SQLite et les uploads seront perdus au redeploy.
- Serveur ARM ou build depuis Mac Apple Silicon : garde `builder.arch: amd64`
  si ton VPS est x86_64.
- VPS avec moins de 1 Go de RAM : ajoute un swapfile avant le premier build,
  sinon `bundle install` peut rester bloque ou se faire tuer par l'OOM killer.

## 12. Variante sans domaine au debut

Pour tester sans HTTPS, retire temporairement la section `proxy.ssl` :

```yaml
proxy:
  app_port: 3000
```

Cette variante est utile pour valider Docker et Kamal, mais le deploy final doit
passer par un domaine et HTTPS.

## Sources

- Documentation officielle Kamal, installation : https://kamal-deploy.org/docs/installation/
- Documentation officielle Kamal, proxy : https://kamal-deploy.org/docs/configuration/proxy/
- Documentation officielle Kamal, variables d'environnement : https://kamal-deploy.org/docs/configuration/environment-variables/
- Documentation officielle Kamal, registry : https://kamal-deploy.org/docs/configuration/docker-registry/
- Documentation officielle Kamal, roles et serveurs : https://kamal-deploy.org/docs/configuration/roles/
