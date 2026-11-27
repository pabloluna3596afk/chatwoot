<script setup>
import { computed, nextTick, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRouter } from 'vue-router';
import { useAlert } from 'dashboard/composables';
import { useAccount } from 'dashboard/composables/useAccount';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import Button from 'dashboard/components-next/button/Button.vue';
import Switch from 'dashboard/components-next/switch/Switch.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';
import CitasStepRow from './CitasStepRow.vue';
import TemplateSubmissionDialog from './TemplateSubmissionDialog.vue';
import TemplatePreviewDrawer from './TemplatePreviewDrawer.vue';

const props = defineProps({
  connected: Boolean,
  expanded: Boolean,
  disabled: Boolean,
  templateData: { type: Object, default: null },
  templateState: { type: Object, required: true },
  loading: Boolean,
  error: Boolean,
  refresh: { type: Function, required: true },
});
const emit = defineEmits(['toggle']);
const { t } = useI18n();
const router = useRouter();
const { accountScopedRoute } = useAccount();
const templateState = computed(() => props.templateState);
const kit = ref(null);
const dialog = ref(null);
const submitButton = ref(null);
const toggleButton = ref(null);
const preview = ref(null);
const submitting = ref(false);
const submitError = ref(false);
const feedback = ref('');
const preparing = ref(false);
const savingReminder = ref(false);
const reminderEnabled = computed(() => kit.value?.reminder_enabled || false);
const reminderApproved = computed(() =>
  templateState.value.functions
    .find(item => item.key === 'reminder')
    ?.perWaba.some(item => item.state === 'approved')
);
const reminderLabel = computed(() => {
  if (reminderEnabled.value) return t('CITAS_SCREEN.REMINDER_ON');
  return reminderApproved.value
    ? t('CITAS_SCREEN.REMINDER_OFF')
    : t('CITAS_SCREEN.REMINDER_LOCKED');
});
const stateLabel = state => {
  switch (state) {
    case 'approved':
      return t('CITAS_SCREEN.STATE.approved');
    case 'review':
      return t('CITAS_SCREEN.STATE.review');
    case 'rejected':
      return t('CITAS_SCREEN.STATE.rejected');
    case 'failed':
      return t('CITAS_SCREEN.STATE.failed');
    default:
      return t('CITAS_SCREEN.STATE.unsent');
  }
};
const countLabel = (state, count) => {
  switch (state) {
    case 'approved':
      return t('CITAS_SCREEN.COUNT.approved', count, { n: count });
    case 'review':
      return t('CITAS_SCREEN.COUNT.review', count, { n: count });
    case 'rejected':
      return t('CITAS_SCREEN.COUNT.rejected', count, { n: count });
    case 'failed':
      return t('CITAS_SCREEN.COUNT.failed', count, { n: count });
    default:
      return t('CITAS_SCREEN.COUNT.unsent', count, { n: count });
  }
};
const stateColor = state => {
  if (state === 'approved') return 'teal';
  if (state === 'review') return 'amber';
  if (state === 'rejected' || state === 'failed') return 'ruby';
  return 'slate';
};
const reviewCount = computed(() =>
  templateState.value.functions.reduce(
    (sum, item) => sum + item.counts.review,
    0
  )
);
const reviewNotice = computed(() =>
  t('CITAS_SCREEN.IN_REVIEW_STRIP', reviewCount.value, {
    n: reviewCount.value,
  })
);
const templates = computed(() => [
  {
    key: 'confirmation',
    title: t('CALENDAR_ACTIVATION_KIT.CONFIRMATION'),
    draftExists: Boolean(
      props.templateData?.results?.confirmation?.draft_exists
    ),
  },
  {
    key: 'cancellation',
    title: t('CALENDAR_ACTIVATION_KIT.CANCELLATION'),
    draftExists: Boolean(
      props.templateData?.results?.cancellation?.draft_exists
    ),
  },
  {
    key: 'reminder',
    title: t('CALENDAR_ACTIVATION_KIT.REMINDER'),
    draftExists: Boolean(props.templateData?.results?.reminder?.draft_exists),
  },
]);
const accountByWaba = wabaId =>
  templateState.value.accounts.find(
    account => account.waba_id === String(wabaId)
  );
const isPending = state => ['unsent', 'rejected', 'failed'].includes(state);
const accountHasPending = account =>
  Boolean(account) &&
  templates.value.some(
    template =>
      template.draftExists && isPending(account.templates[template.key]?.state)
  );
const hasPending = computed(
  () =>
    props.templateData?.results &&
    templates.value.some(template => {
      const result = props.templateData.results[template.key];
      return (
        result?.draft_exists &&
        (result.destinations || []).some(destination =>
          isPending(
            accountByWaba(destination.waba_id)?.templates?.[template.key]?.state
          )
        )
      );
    })
);
const prepared = computed(() =>
  templates.value.every(
    template => props.templateData?.results?.[template.key]?.draft_exists
  )
);
const value = computed(() => {
  if (props.disabled) return t('CITAS_SCREEN.AVAILABLE_WITH_GOOGLE');
  if (props.loading) return '';
  if (!templateState.value.accounts.length)
    return t('CITAS_SCREEN.NO_WHATSAPP');
  const approved = templateState.value.functions.filter(
    item => item.aggregate === 'approved'
  ).length;
  return templateState.value.accounts.length === 1
    ? t('CITAS_SCREEN.SUMMARY_ONE', { n: approved })
    : t('CITAS_SCREEN.SUMMARY_MANY', {
        n: templateState.value.accounts.filter(account =>
          templates.value.every(
            template => account.templates[template.key]?.state === 'approved'
          )
        ).length,
        total: templateState.value.accounts.length,
      });
});
const summaryFor = row => {
  const item = templateState.value.functions.find(
    entry => entry.key === row.key
  );
  if (!templateState.value.accounts.length) return stateLabel('unsent');
  if (templateState.value.accounts.length === 1) {
    const accountItem = item.perWaba[0];
    return `${stateLabel(accountItem.state)}${accountItem.state === 'rejected' && accountItem.reason ? `: "${accountItem.reason}"` : ''}`;
  }
  const counts = item.counts;
  const present = ['approved', 'review', 'rejected', 'failed', 'unsent']
    .filter(state => counts[state])
    .map(state => countLabel(state, counts[state]));
  if (present.length === 1)
    return t('CITAS_SCREEN.ALL_ACCOUNTS', {
      state: stateLabel(item.aggregate),
      n: templateState.value.accounts.length,
    });
  return present.join(' · ');
};
const rows = computed(() =>
  templates.value.map(template => ({
    ...template,
    result: props.templateData?.results?.[template.key] || {},
    state: templateState.value.functions.find(
      item => item.key === template.key
    ),
  }))
);
async function loadKit() {
  try {
    const activation = await CalendarAPI.getActivationKit();
    kit.value = activation.data;
  } catch {
    kit.value = null;
  }
}
const load = async () => {
  await Promise.all([props.refresh(), loadKit()]);
};
const prepare = async () => {
  preparing.value = true;
  try {
    await CalendarAPI.prepareTemplateDrafts(
      props.templateData?.effective_language
    );
    await props.refresh();
  } catch {
    useAlert(t('CALENDAR_TEMPLATES.PREPARE_ERROR'));
  } finally {
    preparing.value = false;
  }
};
const saveReminder = async enabled => {
  if (
    savingReminder.value ||
    (enabled &&
      !templateState.value.functions
        .find(item => item.key === 'reminder')
        ?.perWaba.some(item => item.state === 'approved'))
  )
    return;
  savingReminder.value = true;
  try {
    const response = await CalendarAPI.updateReminderEnabled(enabled);
    kit.value = {
      ...kit.value,
      reminder_enabled: response.data.reminder_enabled,
    };
    useAlert(t('CALENDAR_ACTIVATION_KIT.REMINDER_SAVED'));
  } catch {
    useAlert(t('CALENDAR_ACTIVATION_KIT.REMINDER_SAVE_ERROR'));
  } finally {
    savingReminder.value = false;
  }
};
const previewTemplate = (event, row, accountItem) => {
  const previewKey = {
    confirmation: 'template',
    cancellation: 'cancel_template',
    reminder: 'reminder_template',
  }[row.key];
  preview.value?.open(event.currentTarget, {
    title: row.title,
    state: accountItem?.state || row.state.aggregate,
    statusLabel: stateLabel(accountItem?.state || row.state.aggregate),
    color: stateColor(accountItem?.state || row.state.aggregate),
    reason: accountItem?.state === 'rejected' ? accountItem.reason : '',
    preview: kit.value?.[previewKey],
    language:
      props.templateData?.effective_language ||
      props.templateData?.language ||
      'es',
    draftId: row.result.draft_id,
  });
};
const openCorrection = draftId => {
  router.push(
    accountScopedRoute(
      'settings_templates',
      {},
      draftId ? { draft: String(draftId) } : {}
    )
  );
};
const restoreDialogFocus = async () => {
  await nextTick();
  const submitTrigger = submitButton.value?.$el;
  if (submitTrigger && document.contains(submitTrigger)) {
    submitTrigger.focus();
  } else {
    toggleButton.value?.$el?.focus();
  }
};
const submit = async selection => {
  if (submitting.value) return;
  submitting.value = true;
  submitError.value = false;
  feedback.value = '';
  try {
    const response = await CalendarAPI.submitTemplateDrafts(selection);
    await props.refresh();
    const failedItems = [
      ...(response.data.failed || []),
      ...(response.data.skipped || []),
    ];
    if (failedItems.length) {
      feedback.value = t('CITAS_SCREEN.SUBMIT.PARTIAL', {
        ok: selection.functions.length - failedItems.length,
        total: selection.functions.length,
        failed: failedItems.length,
        reason:
          failedItems[0].reason ||
          t('CALENDAR_TEMPLATES.SUBMISSION.ERRORS.submission_failed'),
      });
      return;
    }
    const otherPending = templateState.value.accounts.find(
      account =>
        account.waba_id !== selection.waba_ids[0] && accountHasPending(account)
    );
    const current = templateState.value.accounts.find(
      account => account.waba_id === selection.waba_ids[0]
    );
    const next = otherPending || (accountHasPending(current) ? current : null);
    if (next) {
      dialog.value?.setAccount(next.waba_id);
      const params = {
        n: selection.functions.length,
        account: next.name || next.number || '',
      };
      feedback.value =
        next.waba_id === current?.waba_id
          ? t('CITAS_SCREEN.SUBMIT.SENT_REMAINING', params)
          : t('CITAS_SCREEN.SUBMIT.SENT_NEXT', params);
      return;
    }
    dialog.value?.close();
    useAlert(t('CITAS_SCREEN.SUBMIT.SENT', { n: selection.functions.length }));
  } catch {
    submitError.value = true;
  } finally {
    submitting.value = false;
  }
};
onMounted(loadKit);
</script>

<template>
  <CitasStepRow
    icon="2"
    :title="$t('CITAS_SCREEN.STEP_MESSAGES')"
    :value="value"
    :expanded="expanded"
    :disabled="disabled"
    data-testid="citas-messages-step"
  >
    <template #actions="{ contentId }">
      <Button
        ref="toggleButton"
        intent="tertiary"
        size="sm"
        :disabled="disabled"
        :label="
          expanded
            ? $t('CITAS_SCREEN.HIDE_MESSAGES')
            : $t('CITAS_SCREEN.SHOW_MESSAGES')
        "
        :aria-expanded="expanded"
        :aria-controls="contentId"
        @click="emit('toggle')"
      />
      <Button
        v-if="hasPending && connected"
        ref="submitButton"
        intent="primary"
        size="sm"
        :label="$t('CITAS_SCREEN.SUBMIT.TITLE')"
        @click="dialog?.open()"
      />
    </template>
    <Spinner v-if="loading" />
    <div v-else-if="error" role="alert" class="text-body-main text-n-ruby-11">
      {{ $t('CALENDAR_TEMPLATES.LOAD_ERROR') }}
      <Button
        intent="secondary"
        :label="$t('CALENDAR_ACTIVATION_KIT.RELOAD')"
        @click="load"
      />
    </div>
    <template v-else>
      <p v-if="!connected" class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.AVAILABLE_WITH_GOOGLE') }}
      </p>
      <template v-else>
        <p
          v-if="!templateState.accounts.length"
          class="m-0 text-body-main text-n-slate-11"
        >
          {{ $t('CITAS_SCREEN.NO_WHATSAPP') }}
          <RouterLink
            :to="accountScopedRoute('settings_inboxes')"
            class="text-n-blue-11 underline"
          >
            {{ $t('CITAS_SCREEN.CONNECT') }}
          </RouterLink>
        </p>
        <p
          v-if="!prepared"
          class="m-0 flex items-center gap-2 text-body-main text-n-slate-11"
        >
          <Spinner /> {{ $t('CITAS_SCREEN.NOT_PREPARED') }}
          <Button
            intent="secondary"
            :label="$t('CALENDAR_TEMPLATES.RETRY')"
            :disabled="preparing"
            :is-loading="preparing"
            @click="prepare"
          />
        </p>
        <p
          v-if="templateData?.language_changed"
          class="m-0 text-body-main text-n-amber-11"
        >
          {{
            $t('CITAS_PANEL.PREPARE_LANGUAGE', {
              language: templateData.effective_language,
            })
          }}
          <Button
            intent="secondary"
            :label="$t('CALENDAR_TEMPLATES.RETRY')"
            @click="prepare"
          />
        </p>
        <div
          v-if="
            templateState.functions.some(item => item.aggregate === 'review')
          "
          class="text-body-main text-n-amber-11"
          aria-live="polite"
        >
          {{ reviewNotice }}
        </div>
        <div
          v-for="row in rows"
          :key="row.key"
          class="grid min-w-0 grid-cols-[minmax(0,1fr)_auto] items-center gap-3 max-sm:grid-cols-1"
          :data-testid="`citas-template-${row.key}`"
        >
          <div class="flex min-w-0 flex-wrap items-center gap-x-3 gap-y-1">
            <button
              type="button"
              class="text-start text-body-main text-n-blue-11 underline"
              :aria-label="$t('CITAS_SCREEN.PREVIEW_ARIA', { name: row.title })"
              @click="
                previewTemplate(
                  $event,
                  row,
                  row.state.perWaba.find(
                    item => item.state === row.state.aggregate
                  ) || row.state.perWaba[0]
                )
              "
            >
              {{ row.title }}
            </button>
            <span
              class="flex items-center gap-2 text-body-main text-n-slate-11"
            >
              <span
                class="size-2 shrink-0 rounded-full"
                :class="
                  row.state.aggregate === 'approved'
                    ? 'bg-n-teal-9'
                    : ['rejected', 'failed'].includes(row.state.aggregate)
                      ? 'bg-n-ruby-9'
                      : row.state.aggregate === 'review'
                        ? 'bg-n-amber-9'
                        : 'bg-n-slate-8'
                "
                aria-hidden="true"
              />
              {{ summaryFor(row) }}
            </span>
          </div>
          <Button
            v-if="row.state.aggregate === 'rejected'"
            intent="tertiary"
            size="sm"
            :label="$t('CITAS_SCREEN.FIX')"
            @click="
              previewTemplate(
                $event,
                row,
                row.state.perWaba.find(item => item.state === 'rejected')
              )
            "
          />
        </div>
        <div class="flex items-start gap-2">
          <Switch
            :model-value="reminderEnabled"
            :disabled="savingReminder || !reminderApproved"
            :aria-label="reminderLabel"
            @update:model-value="saveReminder"
          />
          <div class="text-body-main text-n-slate-11">
            {{ reminderLabel }}
          </div>
        </div>
      </template>
      <TemplateSubmissionDialog
        ref="dialog"
        :accounts="templateState.accounts"
        :templates="templates"
        :is-loading="submitting"
        :error="submitError"
        :feedback="feedback"
        @submit="submit"
        @close="restoreDialogFocus"
      />
      <TemplatePreviewDrawer ref="preview" @correct="openCorrection" />
    </template>
  </CitasStepRow>
</template>
