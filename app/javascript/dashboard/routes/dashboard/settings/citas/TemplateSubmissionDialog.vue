<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const props = defineProps({
  accounts: { type: Array, default: () => [] },
  templates: { type: Array, default: () => [] },
  isLoading: { type: Boolean, default: false },
});
const emit = defineEmits(['submit']);
const { t } = useI18n();
const dialog = ref(null);
const selectedAccounts = ref([]);
const selectedTemplates = ref([]);
const accountCount = computed(() => selectedAccounts.value.length);
const templateCount = computed(() => selectedTemplates.value.length);
const templateLabel = computed(() =>
  templateCount.value === 1
    ? t('CALENDAR_TEMPLATES.SUBMISSION.TEMPLATE_ONE')
    : t('CALENDAR_TEMPLATES.SUBMISSION.TEMPLATE_MANY')
);
const accountLabel = computed(() =>
  accountCount.value === 1
    ? t('CALENDAR_TEMPLATES.SUBMISSION.ACCOUNT_ONE')
    : t('CALENDAR_TEMPLATES.SUBMISSION.ACCOUNT_MANY')
);
const summary = computed(() => {
  if (!accountCount.value || !templateCount.value)
    return t('CALENDAR_TEMPLATES.SUBMISSION.SELECT_REQUIRED');
  return t('CALENDAR_TEMPLATES.SUBMISSION.SUMMARY', {
    templates: templateCount.value,
    templateLabel: templateLabel.value,
    accounts: accountCount.value,
    accountLabel: accountLabel.value,
  });
});
const open = () => {
  selectedAccounts.value = props.accounts.length
    ? [props.accounts[0].waba_id]
    : [];
  selectedTemplates.value = props.templates
    .filter(template => !template.disabled)
    .map(template => template.key);
  dialog.value?.open();
};
const submit = () => {
  emit('submit', {
    waba_ids: selectedAccounts.value,
    functions: selectedTemplates.value,
  });
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="$t('CALENDAR_TEMPLATES.SUBMISSION.TITLE')"
    :description="$t('CALENDAR_TEMPLATES.SUBMISSION.DESCRIPTION')"
    :cancel-button-label="$t('CALENDAR_TEMPLATES.SUBMISSION.CANCEL')"
    :confirm-button-label="$t('CALENDAR_TEMPLATES.SUBMISSION.SEND')"
    :disable-confirm-button="!accountCount || !templateCount"
    :is-loading="isLoading"
    overflow-y-auto
    @confirm="submit"
  >
    <section class="flex flex-col gap-2">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.SUBMISSION.ACCOUNTS') }}
      </h4>
      <label
        v-for="account in accounts"
        :key="account.waba_id"
        class="flex min-w-0 items-start gap-3 rounded-lg border border-n-weak p-3 has-[:checked]:border-n-brand has-[:checked]:bg-n-alpha-2"
      >
        <Checkbox
          :model-value="selectedAccounts.includes(account.waba_id)"
          :aria-label="
            account.channels
              .map(channel => `${channel.name} ${channel.phone_number || ''}`)
              .join(', ')
          "
          @update:model-value="
            checked => {
              selectedAccounts = checked
                ? [...selectedAccounts, account.waba_id]
                : selectedAccounts.filter(id => id !== account.waba_id);
            }
          "
        />
        <span class="min-w-0 break-words text-body-main text-n-slate-12">
          {{
            account.channels
              .map(channel =>
                `${channel.name} ${channel.phone_number || ''}`.trim()
              )
              .join(', ')
          }}
          <span class="block break-all text-xs text-n-slate-11">{{
            $t('CITAS_PANEL.WABA', { id: account.waba_id })
          }}</span>
        </span>
      </label>
      <p v-if="!accounts.length" class="text-body-main text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.SUBMISSION.NO_ACCOUNTS') }}
      </p>
    </section>
    <section class="flex flex-col gap-2">
      <h4 class="text-xs font-semibold uppercase tracking-wide text-n-slate-11">
        {{ $t('CALENDAR_TEMPLATES.SUBMISSION.TEMPLATES') }}
      </h4>
      <label
        v-for="template in templates"
        :key="template.key"
        class="flex min-w-0 items-start gap-3 rounded-lg border border-n-weak p-3 has-[:checked]:border-n-brand has-[:checked]:bg-n-alpha-2"
        :class="template.disabled ? 'cursor-not-allowed opacity-60' : ''"
      >
        <Checkbox
          :model-value="selectedTemplates.includes(template.key)"
          :disabled="template.disabled"
          :aria-label="template.title"
          @update:model-value="
            checked => {
              selectedTemplates = checked
                ? [...selectedTemplates, template.key]
                : selectedTemplates.filter(key => key !== template.key);
            }
          "
        />
        <span class="min-w-0 text-body-main text-n-slate-12">
          {{ template.title }}
          <span class="block text-xs text-n-slate-11">
            {{
              template.disabled
                ? $t('CALENDAR_TEMPLATES.SUBMISSION.ALREADY_SENT')
                : template.description
            }}
          </span>
        </span>
      </label>
    </section>
    <p class="text-body-main text-n-slate-11" aria-live="polite">
      {{ summary }}
    </p>
    <template #footer>
      <div
        class="flex w-full flex-col-reverse gap-3 sm:flex-row sm:justify-end"
      >
        <Button
          intent="secondary"
          type="button"
          :label="$t('CALENDAR_TEMPLATES.SUBMISSION.CANCEL')"
          :disabled="isLoading"
          @click="dialog.close()"
        />
        <Button
          intent="primary"
          type="button"
          :label="$t('CALENDAR_TEMPLATES.SUBMISSION.SEND')"
          :disabled="!accountCount || !templateCount || isLoading"
          :is-loading="isLoading"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
