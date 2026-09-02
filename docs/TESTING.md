# Tests — Chatwoot fork (InboxHub)

## Por qué existe este documento

La imagen de producción se construye con `BUNDLE_WITHOUT=development:test`, así que
el contenedor **no trae rspec ni rubocop**. Y `config/database.yml` hace que el
entorno `test` lea `POSTGRES_DATABASE`, que en el contenedor vale `chatwoot` — tu
base real. Sin las precauciones de abajo, `rails db:test:prepare` **borra tu base
de desarrollo**.

> Rails tiene una protección (`db:check_protected_environments`) que aborta ese
> borrado. **Nunca la desactives con `DISABLE_DATABASE_ENVIRONMENT_CHECK=1`.**

## Preparar el entorno (una vez por contenedor)

Instalar el grupo `test` sin arrastrar `development`:

```powershell
docker exec -e BUNDLE_WITHOUT=development chatwoot-chatwoot-rails-1 bundle install --jobs 4
```

Se pierde al recrear el contenedor (`up --build`), no al reiniciarlo.

## Crear la base de test

Siempre en una base **con otro nombre**, pasando `POSTGRES_DATABASE` explícito:

```powershell
docker exec chatwoot-chatwoot-postgres-1 sh -c "dropdb -U postgres --if-exists chatwoot_test_local && createdb -U postgres chatwoot_test_local"

docker exec -e BUNDLE_WITHOUT=development -e RAILS_ENV=test -e POSTGRES_DATABASE=chatwoot_test_local `
  chatwoot-chatwoot-rails-1 sh -c "bundle exec rails db:schema:load"
```

`db:migrate` desde cero **no funciona**: `20231211010807_add_cached_labels_list.rb`
usa una API de `acts_as_taggable_on` que ya no existe. Por eso `schema.rb` es la
única vía, y por eso mantenerlo sano importa (ver *Si algo falla*).

## Correr tests

```powershell
$env:T = "spec/services/automation_rules/lint_service_spec.rb"
docker exec -e BUNDLE_WITHOUT=development -e RAILS_ENV=test -e POSTGRES_DATABASE=chatwoot_test_local `
  chatwoot-chatwoot-rails-1 sh -c "bundle exec rspec $env:T"
```

`spec/` **no está montado** como volumen (a diferencia de `app/`, `config/`, `db/`,
`lib/`, `enterprise/`). Después de editar un spec hay que copiarlo:

```powershell
docker cp spec chatwoot-chatwoot-rails-1:/app/
```

Un solo ejemplo por número de línea: `bundle exec rspec spec/foo_spec.rb:42`

## Rubocop

```powershell
docker exec -e BUNDLE_WITHOUT=development chatwoot-chatwoot-rails-1 `
  bundle exec rubocop --force-exclusion app/services/... spec/services/...
```

`-a` autocorrige lo seguro, `-A` incluye lo inseguro (revisa el diff después).
El hook de pre-commit intenta correrlo pero falla en silencio con
`xargs: bundle: No such file or directory`, porque `bundle` no existe en el host
Windows. **Rubocop no te cubre al commitear: córrelo a mano.**

## ESLint / Prettier

El hook `pre-commit` sí corre `lint-staged` sobre lo staged. Si ves cientos de
errores `Delete ␍`, tu `core.autocrlf` está en `true`:

```powershell
git config --local core.autocrlf input
```

`input` convierte CRLF→LF al commitear y no reinyecta CR al hacer checkout, que es
lo correcto para un repo que corre en contenedores Linux. Con `true`, prettier
rechaza cada archivo JS/Vue y **ningún commit que toque frontend puede pasar**.

## Estado del CI

Los workflows `Run Chatwoot CE spec` y `Frontend Lint & Test` estuvieron
desactivados (`disabled_manually`) porque la base de test no se podía crear:
`db/schema.rb` estaba corrupto. Corregido en el PR #76.

Comprobar y reactivar:

```powershell
gh workflow list --repo pabloluna3596afk/chatwoot --all
gh workflow enable "Run Chatwoot CE spec" --repo pabloluna3596afk/chatwoot
```

## Si algo falla

| Síntoma | Causa | Qué hacer |
|---|---|---|
| `PG::SyntaxError: syntax error at end of input` al cargar el schema | `schema.rb` con paréntesis desbalanceado | Ya corregido; si vuelve, no edites `schema.rb` a mano |
| `relation "X" does not exist` con la migración aplicada | `schema.rb` perdió la tabla y su migración es anterior a la versión declarada, así que nunca se re-ejecuta | Regenerar `schema.rb` (abajo) |
| `Migrations are pending` en una base recién creada | `schema.rb` va por detrás de `db/migrate/` | `rails db:migrate` sobre la base de test, y commitear el `schema.rb` resultante |
| `Validation failed: Automation conditions X not supported` en un spec | El modelo rechaza claves desconocidas al guardar | Usar `build(...)` en vez de `create(...)` |
| Rubocop no corrió al commitear | `bundle` no está en el host | Correrlo a mano en el contenedor |

### Regenerar `schema.rb` correctamente

Nunca lo edites a mano. Y nunca lo generes desde una base con migraciones
huérfanas aplicadas: clona una base buena, ajústala a las migraciones de la rama,
y vuelca.

```powershell
# 1. Clonar estructura + el registro de migraciones
docker exec chatwoot-chatwoot-postgres-1 sh -c "dropdb -U postgres --if-exists schema_gen && createdb -U postgres schema_gen && pg_dump -U postgres --schema-only chatwoot | psql -U postgres -q -d schema_gen && pg_dump -U postgres --data-only --table=schema_migrations --table=ar_internal_metadata chatwoot | psql -U postgres -q -d schema_gen"

# 2. Comparar lo aplicado contra los archivos de la rama y quitar lo que sobre
docker exec chatwoot-chatwoot-postgres-1 psql -U postgres -d schema_gen -t -A -c "SELECT version FROM schema_migrations ORDER BY version;"
# ...contra: Get-ChildItem db\migrate\*.rb | ForEach-Object { ($_.Name -split '_')[0] }

# 3. Volcar (db/ está montado, sale al host)
docker exec -e BUNDLE_WITHOUT=development -e RAILS_ENV=test -e POSTGRES_DATABASE=schema_gen `
  chatwoot-chatwoot-rails-1 sh -c "bundle exec rails db:schema:dump"
```

**Verificar antes de commitear.** El diff se reordena solo, así que leerlo no
sirve: carga el schema en una base vacía y compara estructura contra el origen.

```powershell
docker exec chatwoot-chatwoot-postgres-1 sh -c "dropdb -U postgres --if-exists schema_check && createdb -U postgres schema_check"
docker exec -e BUNDLE_WITHOUT=development -e RAILS_ENV=test -e POSTGRES_DATABASE=schema_check `
  chatwoot-chatwoot-rails-1 sh -c "bundle exec rails db:schema:load"

$q = "SELECT table_name||'.'||column_name||':'||data_type FROM information_schema.columns WHERE table_schema='public' ORDER BY 1;"
docker exec chatwoot-chatwoot-postgres-1 psql -U postgres -d schema_gen   -t -A -c $q > ref.txt
docker exec chatwoot-chatwoot-postgres-1 psql -U postgres -d schema_check -t -A -c $q > new.txt
Compare-Object (Get-Content ref.txt) (Get-Content new.txt)   # vacío = correcto
```

Repite lo mismo con `SELECT indexname FROM pg_indexes WHERE schemaname='public' ORDER BY 1;`.
