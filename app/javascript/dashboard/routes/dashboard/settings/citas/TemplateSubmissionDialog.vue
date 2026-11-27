<script setup>
import { computed, nextTick, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accounts: { type: Array, default: () => [] },
  templates: { type: Array, default: () => [] },
  isLoading: Boolean,
  error: Boolean,
  feedback: { type: String, default: '' },
});
const emit = defineEmits(['submit', 'close']);
const { t } = useI18n();
const description = computed(() =>
  props.accounts.length > 1
    ? t('CITAS_SCREEN.SUBMIT.DESC_MANY')
    : t('CITAS_SCREEN.SUBMIT.DESC_ONE')
);
const dialog = ref(null);
const selectedWaba = ref('');
const selectedTemplates = ref([]);
const currentAccount = computed(() =>
  props.accounts.find(account => account.waba_id === selectedWaba.value)
);
const pendingTemplates = computed(() =>
  props.templates.filter(
    template =>
      template.draftExists &&
      ['unsent', 'rejected', 'failed'].includes(
        currentAccount.value?.templates?.[template.key]?.state || 'unsent'
      )
  )
);
const selectedCount = computed(() => selectedTemplates.value.length);
const templateDisabled = template =>
  !template.draftExists ||
  !['unsent', 'rejected', 'failed'].includes(
    currentAccount.value?.templates?.[template.key]?.state || 'unsent'
  );
const stateColor = state =>
  ({
    approved: 'bg-n-teal-9',
    review: 'bg-n-amber-9',
    rejected: 'bg-n-ruby-9',
    failed: 'bg-n-ruby-9',
    unsent: 'bg-n-slate-8',
  })[state] || 'bg-n-slate-8';
const stateLabel = item => {
  let label;
  switch (item?.state) {
    case 'approved':
      label = t('CITAS_SCREEN.STATE.approved');
      break;
    case 'review':
      label = t('CITAS_SCREEN.STATE.review');
      break;
    case 'rejected':
      label = t('CITAS_SCREEN.STATE.rejected');
      break;
    case 'failed':
      label = t('CITAS_SCREEN.STATE.failed');
      break;
    default:
      label = t('CITAS_SCREEN.STATE.unsent');
  }
  const reason =
    item?.reason && item.state === 'rejected' ? `: "${item.reason}"` : '';
  return `${label}${reason}`;
};
const worstState = account =>
  ['failed', 'rejected', 'unsent', 'review', 'approved'].find(state =>
    Object.values(account.templates || {}).some(item => item.state === state)
  ) || 'unsent';
const options = computed(() =>
  props.accounts.map(account => {
    const approved = Object.values(account.templates || {}).filter(
      item => item.state === 'approved'
    ).length;
    return {
      value: account.waba_id,
      label: `${account.name || account.number || account.waba_id} · ${t('CITAS_SCREEN.SUBMIT.OPTION', { number: account.number || '', n: approved })} · ● ${stateLabel({ state: worstState(account) })}`,
    };
  })
);
const setAccount = wabaId => {
  selectedWaba.value = String(wabaId || '');
  selectedTemplates.value = pendingTemplates.value.map(
    template => template.key
  );
};
watch(
  () => props.accounts,
  accounts => {
    if (!accounts.some(account => account.waba_id === selectedWaba.value)) {
      const firstPending = accounts.find(account =>
        Object.values(account.templates || {}).some(item =>
          ['unsent', 'rejected', 'failed'].includes(item.state)
        )
      );
      setAccount(firstPending?.waba_id || accounts[0]?.waba_id);
      return;
    }
    const pending = new Set(
      pendingTemplates.value.map(template => template.key)
    );
    const remaining = selectedTemplates.value.filter(key => pending.has(key));
    selectedTemplates.value = remaining.length
      ? remaining
      : pendingTemplates.value.map(template => template.key);
  },
  { immediate: true, deep: true }
);
const open = async () => {
  const firstPending = props.accounts.find(account =>
    Object.values(account.templates || {}).some(item =>
      ['unsent', 'rejected', 'failed'].includes(item.state)
    )
  );
  setAccount(firstPending?.waba_id || props.accounts[0]?.waba_id);
  await dialog.value?.open();
  await nextTick();
  const focusTarget =
    props.accounts.length > 1
      ? document.getElementById('citas-waba-account')
      : document.querySelector('[data-testid="submit-templates"]');
  focusTarget?.focus();
};
const selectAccount = wabaId => setAccount(wabaId);
const submit = () => {
  if (props.isLoading || !selectedTemplates.value.length || !selectedWaba.value)
    return;
  emit('submit', {
    waba_ids: [selectedWaba.value],
    functions: [...selectedTemplates.value],
  });
};
defineExpose({
  open,
  close: () => dialog.value?.close(),
  setAccount: selectAccount,
});
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="$t('CITAS_SCREEN.SUBMIT.TITLE')"
    :description="description"
    :cancel-button-label="$t('CITAS_SCREEN.SUBMIT.CANCEL')"
    :confirm-button-label="$t('CITAS_SCREEN.SUBMIT.SEND')"
    :disable-confirm-button="!selectedCount || !pendingTemplates.length"
    :is-loading="isLoading"
    body-scroll
    @confirm="submit"
    @close="emit('close')"
  >
    <div class="flex flex-col gap-4">
      <div v-if="accounts.length > 1" class="flex flex-col gap-1">
        <label class="text-sm font-medium text-n-slate-12">{{
          $t('CITAS_SCREEN.SUBMIT.ACCOUNT')
        }}</label>
        <ComboBox
          id="citas-waba-account"
          :model-value="selectedWaba"
          :options="options"
          :show-search="false"
          :allow-deselect="false"
          :aria-label="$t('CITAS_SCREEN.SUBMIT.ACCOUNT')"
          @update:model-value="setAccount"
        />
      </div>
      <p class="m-0 text-body-main text-n-slate-11">
        {{ $t('CITAS_SCREEN.SUBMIT.TEMPLATES') }}
      </p>
      <div class="flex flex-col gap-2">
        <label
          v-for="template in templates"
          :key="template.key"
          class="flex min-w-0 items-start gap-3 py-2"
          :class="
            templateDisabled(template) ? 'cursor-not-allowed opacity-75' : ''
          "
        >
          <Checkbox
            :model-value="selectedTemplates.includes(template.key)"
            :disabled="templateDisabled(template) || isLoading"
            :aria-label="template.title"
            @update:model-value="
              checked =>
                (selectedTemplates = checked
                  ? [...selectedTemplates, template.key]
                  : selectedTemplates.filter(key => key !== template.key))
            "
          />
          <span class="min-w-0 flex-1 text-body-main text-n-slate-12">
            {{ template.title }}
            <span class="flex items-center gap-2 text-sm text-n-slate-11">
              <span
                class="size-2 shrink-0 rounded-full"
                :class="
                  stateColor(currentAccount?.templates?.[template.key]?.state)
                "
                aria-hidden="true"
              />
              {{ stateLabel(currentAccount?.templates?.[template.key]) }}
            </span>
          </span>
        </label>
      </div>
      <p class="m-0 text-body-main text-n-slate-11" aria-live="polite">
        {{
          selectedCount
            ? $t('CITAS_SCREEN.SUBMIT.SUMMARY', { n: selectedCount })
            : pendingTemplates.length
              ? $t('CITAS_SCREEN.SUBMIT.NONE_SELECTED')
              : $t('CITAS_SCREEN.SUBMIT.NOTHING_PENDING')
        }}
      </p>
      <p
        v-if="feedback"
        role="status"
        class="m-0 text-body-main text-n-slate-11"
      >
        {{ feedback }}
      </p>
      <p v-if="error" role="alert" class="m-0 text-body-main text-n-ruby-11">
        {{ $t('CITAS_SCREEN.SUBMIT.ERROR') }}
      </p>
    </div>
    <template #footer>
      <div
        class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:justify-end"
      >
        <Button
          intent="secondary"
          type="button"
          :label="$t('CITAS_SCREEN.SUBMIT.CANCEL')"
          :disabled="isLoading"
          @click="dialog.close()"
        />
        <Button
          intent="primary"
          type="button"
          :label="$t('CITAS_SCREEN.SUBMIT.SEND')"
          :disabled="!selectedCount || !pendingTemplates.length || isLoading"
          :is-loading="isLoading"
          data-testid="submit-templates"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
