<script setup>
import { computed, onMounted, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAccount } from 'dashboard/composables/useAccount';
import { useStore } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useAlert } from 'dashboard/composables';
import SectionLayout from './SectionLayout.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';

const { t } = useI18n();
const { isAdmin } = useAdmin();
const { currentAccount, accountId, updateAccount } = useAccount();
const store = useStore();
const cap = ref(50);
const saving = ref(false);
const error = ref('');
const valid = computed(
  () => Number.isInteger(cap.value) && cap.value >= 0 && cap.value <= 10000
);
const usage = computed(() => currentAccount.value?.captain_template_cap);
watch(
  usage,
  value => {
    if (value) cap.value = value.cap;
  },
  { immediate: true }
);
onMounted(async () => {
  try {
    const account = await store.dispatch('accounts/get', {
      accountId: accountId.value,
    });
    if (!account) throw new Error();
  } catch {
    error.value = t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.ERROR');
  }
});
const save = async () => {
  if (!valid.value || !isAdmin.value || saving.value) return;
  saving.value = true;
  error.value = '';
  try {
    await updateAccount({ captain_template_daily_cap: cap.value });
    const account = await store.dispatch('accounts/get', {
      accountId: accountId.value,
    });
    if (!account) throw new Error();
    useAlert(t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.SUCCESS'));
  } catch {
    error.value = t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.ERROR');
  } finally {
    saving.value = false;
  }
};
</script>

<template>
  <SectionLayout
    v-if="isAdmin"
    with-border
    :title="t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.TITLE')"
    :description="t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.NOTE')"
  >
    <div class="flex flex-col gap-3">
      <div class="flex flex-wrap items-center gap-3">
        <Input
          v-model.number="cap"
          type="number"
          min="0"
          max="10000"
          class="w-24"
          :disabled="saving"
          :aria-label="t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.LABEL')"
        />
        <span v-if="usage" class="text-sm text-n-slate-11">{{
          t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.TODAY', usage)
        }}</span>
      </div>
      <p v-if="!valid || error" role="alert" class="text-sm text-n-ruby-11">
        {{ error || t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.INVALID') }}
      </p>
      <Button
        intent="primary"
        class="self-start"
        :disabled="!valid || saving"
        :is-loading="saving"
        :label="t('GENERAL_SETTINGS.FORM.CAPTAIN_TEMPLATE_CAP.SAVE')"
        @click="save"
      />
    </div>
  </SectionLayout>
</template>
