# PR T — owner corrections, 2026-10-08

## CI diagnosis

Run 37725166886 failed in backend shards 16/4, 16/9 and 16/2. All six examples
expected Spanish `Flow completado`, but executed under the default English locale,
whose existing strings remain `Formulario completado`. Commit c31e81313b scopes
the relevant formatter, save-response and incoming-response examples with
`I18n.with_locale(:es)`; production English strings are preserved.

## Shared presentation

- Rows open preview (templates) or editor (Flows), including Enter on a focused
  row. Inner buttons stop propagation. Only edit, duplicate and delete remain;
  all use the existing outline/slate/sm props and pencil/copy/trash icons.
- Reuse `TemplatesToolbar.vue` for both tabs, including the single primary-action
  prop (label and callback), search, filters and action slots. Keep the approved
  Plantillas toolbar container: flex-wrap, gap-3, mb-4; search w-56, gap-2 for
  controls; compact sync precedes create in its actions slot. Flows uses that
  exact component rather than a separate header action. Presets keeps its body;
  its page action uses the same toolbar slot. The toolbar remains available when
  the template list is empty or loading. BaseSettingsHeader is unchanged.
- Inspection of origin/develop Index.vue also found the older BaseSettingsHeader
  actions slot and search/filter controls alongside its tabs. This PR's approved
  build had already extracted those controls into TemplatesToolbar; this revision
  reuses that extraction without adding another toolbar or changing header internals.
- `templateTableColumns.js` owns common Name (leading WhatsApp logo), Category,
  Inbox, Status/Publication, Updated and Actions columns. Templates additionally
  carry Language and Type; Flows carry Screens. Both use TemplatesTable and the
  same status color families. Flow Inbox denotes account-wide eligible scope,
  not proof that every inbox has a successful publication. Template Updated is
  the last synchronization timestamp exposed by the existing endpoint, not a
  Meta edit timestamp.
- Search/filter changes reset page 1 on both. Template search is immediate over
  the synchronized client list; Flow search/filter requests retain the existing
  200 ms debounce and server pagination. Both keep state across tabs and show
  the existing empty-result state. This difference avoids one server request per
  keystroke and preserves upstream client search. Templates offer 10/25/50;
  Flows retain the existing 8-row server page. The same flex wrapping, control
  height, search width and spacing apply at 1280 and 900 px; filter counts differ
  because templates have four meaningful filters and Flows have two.

## Grouped templates — design only

A reusable local definition can be authored once, then submitted as a separate
Meta template per distinct WABA. Meta's official create endpoint is scoped to
`/{waba-id}/message_templates` ([Meta collection](https://www.postman.com/meta/whatsapp-business-platform/request/uvx80vi/create-template-w-text-header-text-body-text-footer-and-2-quick-reply-buttons)).
In this repo `app/services/whatsapp/facebook_api_client.rb:52` fetches by WABA;
`templateUtils.js:33` already deduplicates inboxes sharing a WABA/template ID.
`app/services/whatsapp/flows/cloud_channels.rb:7` provides the same WABA
deduplication precedent for Flow publication.

Future work: persist a local definition/version (name, language, category,
components) and one submission record per distinct WABA, with Meta ID, status,
rejection reason and version. Select inboxes, deduplicate their WABA IDs, create
once per WABA, and expose all associated inbox names in the detail panel. Do not
merge unrelated existing templates solely by name: adoption needs explicit
mapping or an identical definition/version. Media examples may require a new
upload handle per target; target credentials and approval remain per WABA.

Reuse the Flow summary chip and detail-panel presentation through configurable
labels and template states: Approved, Pending, Rejected, Not submitted. Table
summary `Aprobada en 10 de 12` opens five WABAs per detail page, with inbox names,
reason and retry only for failed submissions. Retry affects only that WABA;
approved copies remain intact. Sending messages still uses the selected inbox's
approved template and its language. This PR implements none of these persistence,
submission or retry APIs; its two grouped screenshots are labeled design studies.
The current per-inbox list and fetch/sync logic are retained.

## Publication-detail cache and validation

FlowPublicationPanel caches successful responses by Flow ID, page, search and
state for its component lifetime. Open restores a matching result synchronously
and starts a background request immediately (the previous 200 ms open debounce
is removed). Filters retain their debounce. Cached rows stay visible during a
request or refresh error; another Flow never sees the previous Flow's rows.
No eager request for every visible row is added.

Eight panel tests pass, including a deliberately unresolved 1-second refresh:
cached rows are present immediately and throughout that interval, with no
spinner; refreshed data replaces them when the response arrives. Table/index/
Flows integration tests verify row click/Enter, propagation, permissions,
pagination, filters, duplicates and shared actions. Browser timing and capture
evidence are recorded after the final preset session; fixture network latency
does not measure production Rails/Meta performance.

Rubocop: read-only chathub-rubocop-ci, repository configuration, all three locale
spec files: three inspected, zero offenses. The image's direct installed Rubocop
is used because Bundler rejects its Ruby 3.4.11 against this Gemfile's 3.4.4.
RSpec cannot run locally. No authenticated live API or Meta submission is claimed.
