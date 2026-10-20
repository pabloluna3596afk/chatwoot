# PR 172 — revisión de CI

Fecha: 2026-10-20
Repo: `pabloluna3596afk/chatwoot`
Run inspeccionado: [39182488686](https://github.com/pabloluna3596afk/chatwoot/actions/runs/39182488686)

## `task_plans_spec.rb`: precisión de timestamps

El run falló dos veces en `preserves every persisted attribute, assignment and usage on repeated runs`. `created_at` y `updated_at` del snapshot en memoria tenían nanosegundos (`...823130507`); PostgreSQL devolvió microsegundos (`...823130000`). El seed no era la causa.

El spec ahora toma los snapshots iniciales de `plan`, `account` y `account_plan_usages` tras `reload`. La comparación sigue cubriendo todos los atributos persistidos, asignación y uso, y conserva la segunda invocación idempotente. Revisé los specs nuevos/modificados del PR: no encontré otras comparaciones de atributos completos con este mismo riesgo de precisión.

## `/app/login`: flake ajeno al PR

En el run 39182488686 el ejemplo falló inicialmente con HTTP 500. El runner lo reintentó inmediatamente y obtuvo `1 example, 0 failures`. El job `backend-tests` del run de `develop` 39181382389 también concluyó `success` ([run](https://github.com/pabloluna3596afk/chatwoot/actions/runs/39181382389)).

El PR no modifica `dashboard_controller_spec.rb`, vistas ni assets del dashboard. Su única modificación de rutas agrega `resources :plans` bajo `/api/v1/accounts`; no participa en `/app/login`. Evidencia consistente con un fallo intermitente ajeno al PR; no se cambió el dashboard.

## Rubocop

Ejecutado con `chathub-rubocop-ci:latest`, montaje del repo solo lectura y `MSYS_NO_PATHCONV=1`, sobre `spec/lib/tasks/rake/task_plans_spec.rb`. Resultado: `inspected_file_count: 1`, `offense_count: 0`.
