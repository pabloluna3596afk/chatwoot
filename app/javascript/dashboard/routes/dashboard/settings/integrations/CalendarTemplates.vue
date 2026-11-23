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

const props = defineProps({ connected: { type: Boolean, default: false } });
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
const kit = ref(null);
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
const canEnableReminder = computed(() => {
  const reminder = results.value.reminder;
  return (
    props.connected &&
    reminder?.approved &&
    reminder?.linked &&
    reminder?.draft_exists &&
    !reminder?.archived &&
    reminder?.status !== 'conflict'
  );
});
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
    results.value = drafts.data.results;
    kit.value = activation.data;
  } catch {
    loadFailed.value = true;
  } finally {
    loading.value = false;
  }
};
const prepare = async () => {
  preparing.value = true;
  try {
    const { data } = await CalendarAPI.prepareTemplateDrafts();
    results.value = data.results;
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
      <div
        v-for="row in rows"
        :key="row.key"
        class="grid min-w-0 gap-4 p-3 border rounded-xl border-n-weak md:grid-cols-[18.75rem_minmax(0,1fr)]"
        :data-testid="`calendar-template-${row.key}`"
      >
        <WhatsAppBubble
          v-if="row.preview"
          :body="row.preview.body"
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
