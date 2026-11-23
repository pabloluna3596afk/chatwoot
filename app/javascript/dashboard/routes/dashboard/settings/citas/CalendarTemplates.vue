<script setup>
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import { useAdmin } from 'dashboard/composables/useAdmin';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Label from 'dashboard/components-next/label/Label.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import WhatsAppBubble from 'dashboard/components-next/whatsapp/WhatsAppBubble.vue';
import { fillExamples } from './calendarTemplatePreview';

const props = defineProps({ connected: { type: Boolean, default: false } });
const emit = defineEmits(['updated']);
const FUNCTIONS = [
  { key: 'confirmation', template: 'template', label: 'CONFIRMATION' },
  { key: 'cancellation', template: 'cancel_template', label: 'CANCELLATION' },
  { key: 'reminder', template: 'reminder_template', label: 'REMINDER' },
];
const COLORS = {
  draft: 'slate',
  pending: 'slate',
  archived: 'slate',
  conflict: 'ruby',
  missing: 'slate',
  PENDING: 'amber',
  IN_APPEAL: 'amber',
  APPROVED: 'teal',
  REJECTED: 'ruby',
  PAUSED: 'amber',
  DISABLED: 'ruby',
};
const { t, te } = useI18n();
const { isAdmin } = useAdmin();
const { accountScopedRoute } = useAccount();
const router = useRouter();
const results = ref({});
const language = ref(null);
const kit = ref(null);
const languageState = ref({});
const linking = ref('');
const linkErrors = ref({});
const loading = ref(true);
const loadFailed = ref(false);
const preparing = ref(false);
const savingReminder = ref(false);
const localStatus = result => {
  if (result.archived) return 'archived';
  if (result.status === 'conflict') return 'conflict';
  return result.draft_exists ? 'draft' : 'pending';
};
const metaStatus = result => {
  if (result.remote_status) return result.remote_status;
  return result.submitted ||
    ['submitting', 'reconciling'].includes(result.submission_status)
    ? 'PENDING'
    : 'missing';
};
const rows = computed(() =>
  FUNCTIONS.map(item => {
    const result = results.value[item.key] || {};
    const preview = kit.value?.[item.template];
    return {
      ...item,
      result,
      preview,
      local: localStatus(result),
      meta: metaStatus(result),
    };
  })
);
const reminderDestinations = computed(
  () => results.value.reminder?.destinations || []
);
const canEnableReminder = computed(
  () =>
    props.connected &&
    reminderDestinations.value.some(
      destination => destination.state === 'usable'
    )
);
const partialReminder = computed(
  () =>
    canEnableReminder.value &&
    reminderDestinations.value.some(
      destination => destination.state !== 'usable'
    )
);
const apply = data => {
  results.value = data.results;
  language.value = data.language;
  languageState.value = data;
};
const publish = () =>
  emit('updated', { drafts: languageState.value, kit: kit.value });
const destinationKey = (row, destination) =>
  `${row.key}:${destination.waba_id}`;
const link = async (row, destination) => {
  const key = destinationKey(row, destination);
  linking.value = key;
  linkErrors.value[key] = '';
  try {
    const { data } = await CalendarAPI.linkTemplateDraft({
      function: row.key,
      draft_id: row.result.draft_id,
      channel_id: destination.channels[0].id,
    });
    apply(data);
    publish();
  } catch (error) {
    const reason = error.response?.data?.error;
    const translation = `CITAS_PANEL.LINK_REASONS.${reason}`;
    linkErrors.value[key] = te(translation)
      ? t(translation)
      : t('CITAS_PANEL.LINK_ERROR', {
          reason: reason || t('CITAS_PANEL.SECTION_ERROR'),
        });
  } finally {
    linking.value = '';
  }
};
const reasonLabel = result => {
  const key = `CALENDAR_TEMPLATES.REASONS.${result.reason}`;
  return te(key) ? t(key) : t('CALENDAR_TEMPLATES.REASONS.incompatible');
};
const load = async () => {
  if (!isAdmin.value) {
    loading.value = false;
    return;
  }
  loading.value = true;
  loadFailed.value = false;
  try {
    const [drafts, activation] = await Promise.all([
      CalendarAPI.getTemplateDrafts(),
      CalendarAPI.getActivationKit(),
    ]);
    apply(drafts.data);
    kit.value = activation.data;
    publish();
  } catch {
    loadFailed.value = true;
  } finally {
    loading.value = false;
  }
};
const prepare = async () => {
  preparing.value = true;
  try {
    const { data } = await CalendarAPI.prepareTemplateDrafts(
      languageState.value.effective_language
    );
    apply(data);
    publish();
  } catch {
    useAlert(t('CALENDAR_TEMPLATES.PREPARE_ERROR'));
  } finally {
    preparing.value = false;
  }
};
const openTemplates = result =>
  router.push(
    accountScopedRoute(
      'settings_templates',
      {},
      result.draft_exists ? { draft: String(result.draft_id) } : {}
    )
  );
const saveReminder = async enabled => {
  if (
    !isAdmin.value ||
    savingReminder.value ||
    (enabled && !canEnableReminder.value)
  )
    return;
  savingReminder.value = true;
  try {
    const { data } = await CalendarAPI.updateReminderEnabled(enabled);
    kit.value.reminder_enabled = data.reminder_enabled;
    publish();
    useAlert(t('CALENDAR_ACTIVATION_KIT.REMINDER_SAVED'));
  } catch {
    useAlert(t('CALENDAR_ACTIVATION_KIT.REMINDER_SAVE_ERROR'));
  } finally {
    savingReminder.value = false;
  }
};
onMounted(load);
</script>

<template>
  <section
    class="flex min-w-0 flex-col gap-4 p-4 border rounded-xl border-n-weak"
    data-testid="calendar-templates"
  >
    <div>
      <h3 class="text-heading-1 text-n-slate-12">
        {{ $t('CALENDAR_TEMPLATES.TITLE') }}
      </h3>
      <p class="mt-1 text-body-main text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.DESCRIPTION') }}
      </p>
    </div>
    <p v-if="!isAdmin" class="text-body-main text-n-slate-11">
      {{ $t('CALENDAR_TEMPLATES.ADMIN_ONLY') }}
    </p>
    <Spinner v-else-if="loading" />
    <div
      v-else-if="loadFailed"
      role="alert"
      class="flex flex-wrap gap-2 text-body-main text-n-ruby-11"
    >
      {{ $t('CALENDAR_TEMPLATES.LOAD_ERROR') }}
      <Button
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="load"
      />
    </div>
    <template v-else>
      <p v-if="!connected" class="text-body-main text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.CONNECT_GOOGLE') }}
      </p>
      <p
        v-else-if="
          !Object.keys(results).length ||
          rows.every(row => row.local === 'pending')
        "
        class="text-body-main text-n-slate-11"
      >
        {{ $t('CALENDAR_TEMPLATES.NOT_PREPARED') }}
      </p>
      <p
        v-if="languageState.effective_language"
        class="text-body-main text-n-slate-11"
      >
        {{
          $t('CITAS_PANEL.LANGUAGES', {
            prepared:
              languageState.prepared_language ||
              $t('CALENDAR_TEMPLATES.NOT_SENT'),
            effective: languageState.effective_language,
          })
        }}
      </p>
      <Button
        v-if="languageState.language_changed"
        intent="secondary"
        :label="
          $t('CITAS_PANEL.PREPARE_LANGUAGE', {
            language: languageState.effective_language,
          })
        "
        :disabled="!connected || preparing"
        data-testid="prepare-language"
        @click="prepare"
      />
      <div
        v-for="row in rows"
        :key="row.key"
        class="grid min-w-0 gap-4 p-3 border rounded-xl border-n-weak md:grid-cols-[18.75rem_minmax(0,1fr)]"
        :data-testid="`calendar-template-${row.key}`"
      >
        <WhatsAppBubble
          v-if="row.preview"
          :body="fillExamples(row.preview.body, language)"
          :buttons="row.preview.buttons || []"
        />
        <div class="flex min-w-0 flex-col items-start gap-2">
          <h4 class="m-0 text-body-main font-medium text-n-slate-12">
            {{ $t(`CALENDAR_ACTIVATION_KIT.${row.label}`) }}
          </h4>
          <div
            class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
          >
            {{ $t('CALENDAR_TEMPLATES.LOCAL') }}
            <Label
              :label="$t(`CALENDAR_TEMPLATES.LOCAL_STATUS.${row.local}`)"
              :color="COLORS[row.local]"
              compact
              role="status"
              :data-testid="`local-${row.key}`"
            />
          </div>
          <div
            class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
          >
            {{ $t('CALENDAR_TEMPLATES.META') }}
            <Label
              :label="
                row.meta === 'missing'
                  ? $t('CALENDAR_TEMPLATES.NOT_SENT')
                  : $t(
                      `CALENDAR_ACTIVATION_KIT.STATUS.${row.meta.toLowerCase()}`
                    )
              "
              :color="COLORS[row.meta] || 'slate'"
              compact
              role="status"
              :data-testid="`meta-${row.key}`"
            />
          </div>
          <p
            v-if="row.result.status === 'conflict' || row.result.archived"
            class="m-0 text-body-main text-n-ruby-11"
            role="alert"
          >
            {{
              reasonLabel(
                row.result.archived ? { reason: 'archived_draft' } : row.result
              )
            }}
          </p>
          <div
            v-for="destination in row.result.destinations || []"
            :key="destination.waba_id"
            class="flex w-full min-w-0 flex-col gap-2 border-t border-n-weak pt-3"
            :data-testid="`destination-${row.key}-${destination.waba_id}`"
          >
            <p class="text-body-main text-n-slate-12 break-words">
              {{ destination.channels.map(channel => channel.name).join(', ') }}
            </p>
            <p class="text-xs text-n-slate-11 break-all">
              {{ $t('CITAS_PANEL.WABA', { id: destination.waba_id }) }}
            </p>
            <Label
              :label="
                $t(
                  destination.reason === 'explicit_link_required'
                    ? 'CITAS_PANEL.UNLINKED'
                    : `CITAS_PANEL.DESTINATION_STATES.${destination.state}`
                )
              "
              :color="destination.state === 'usable' ? 'teal' : 'amber'"
              compact
              role="status"
            />
            <p
              v-if="destination.via && destination.via !== 'none'"
              class="text-body-main text-n-slate-11"
            >
              {{ $t(`CITAS_PANEL.VIA.${destination.via}`) }}
            </p>
            <Button
              v-if="
                destination.state !== 'usable' &&
                row.result.draft_exists &&
                destination.channels.length
              "
              intent="secondary"
              :label="$t('CITAS_PANEL.LINK')"
              :disabled="Boolean(linking) || !connected"
              :is-loading="linking === destinationKey(row, destination)"
              @click="link(row, destination)"
            />
            <p
              v-if="linkErrors[destinationKey(row, destination)]"
              role="alert"
              class="text-body-main text-n-ruby-11"
            >
              {{ linkErrors[destinationKey(row, destination)] }}
            </p>
          </div>
          <p
            v-if="!row.result.destinations?.length"
            class="text-body-main text-n-slate-11"
          >
            {{ $t('CITAS_PANEL.NO_DESTINATIONS') }}
          </p>
          <div v-if="row.key === 'reminder'" class="flex items-start gap-2">
            <Switch
              :model-value="kit?.reminder_enabled || false"
              :disabled="
                savingReminder || (!kit?.reminder_enabled && !canEnableReminder)
              "
              aria-labelledby="calendar-reminder-label"
              aria-describedby="calendar-reminder-hint"
              data-testid="calendar-reminder-switch"
              @update:model-value="saveReminder"
            />
            <div>
              <p
                id="calendar-reminder-label"
                class="m-0 text-body-main text-n-slate-12"
              >
                {{ $t('CALENDAR_TEMPLATES.REMINDER_TOGGLE') }}
              </p>
              <p
                v-if="!canEnableReminder"
                id="calendar-reminder-hint"
                class="m-0 text-body-main text-n-slate-11"
              >
                {{ $t('CALENDAR_TEMPLATES.REMINDER_LOCKED') }}
              </p>
              <p v-if="partialReminder" class="text-body-main text-n-amber-11">
                {{ $t('CITAS_PANEL.PARTIAL') }}
              </p>
              <p class="mt-1 text-body-main text-n-slate-11">
                {{ $t('CALENDAR_ACTIVATION_KIT.REMINDER_COST') }}
              </p>
            </div>
          </div>
          <Button
            intent="secondary"
            :label="$t('CALENDAR_TEMPLATES.OPEN')"
            :data-testid="`open-${row.key}`"
            @click="openTemplates(row.result)"
          />
        </div>
      </div>
      <div class="flex flex-wrap gap-2">
        <Button
          intent="secondary"
          :label="$t('CALENDAR_TEMPLATES.RETRY')"
          :disabled="!connected || preparing"
          :is-loading="preparing"
          data-testid="prepare-templates"
          @click="prepare"
        />
        <Button
          intent="tertiary"
          :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
          :disabled="preparing"
          @click="load"
        />
      </div>
    </template>
  </section>
</template>
