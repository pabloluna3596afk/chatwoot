<script setup>
// "Probar": sends the saved flow to a phone number as a flow message through one WhatsApp Cloud channel, without
// publishing it. Meta only delivers it inside the 24 h window of that number; if it refuses, its reason is shown here.
import { computed, ref, watch } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  // [{ waba_id, channel_id, phone_number }]
  wabas: { type: Array, default: () => [] },
  // The request to send: ({ channelId, phoneNumber }) => Promise<{ data }>.
  send: { type: Function, required: true },
});

const dialog = ref(null);
const channelId = ref(null);
const phoneNumber = ref('');
const isSending = ref(false);
// { ok, text } of the last try
const result = ref(null);

const channelOptions = computed(() =>
  props.wabas.map(waba => ({
    value: waba.channel_id,
    label: [waba.inbox_name, waba.phone_number].filter(Boolean).join(' · '),
  }))
);

watch(
  () => props.wabas,
  wabas => {
    if (!wabas.some(waba => waba.channel_id === channelId.value)) {
      channelId.value = wabas[0]?.channel_id ?? null;
    }
  },
  { immediate: true }
);

const canSend = computed(
  () =>
    !isSending.value && channelId.value && phoneNumber.value.replace(/\D/g, '')
);

const open = () => {
  result.value = null;
  dialog.value?.open();
};
const close = () => dialog.value?.close();

const submit = async () => {
  isSending.value = true;
  result.value = null;
  try {
    await props.send({
      channelId: channelId.value,
      phoneNumber: phoneNumber.value.trim(),
    });
    result.value = { ok: true, text: phoneNumber.value.trim() };
  } catch (error) {
    result.value = {
      ok: false,
      text: error?.response?.data?.error || error?.message || '',
    };
  } finally {
    isSending.value = false;
  }
};

defineExpose({ open, close });
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="$t('WHATSAPP_FLOWS.META.TEST_TITLE')"
    :description="$t('WHATSAPP_FLOWS.META.TEST_DESCRIPTION')"
    data-testid="flow-test-dialog"
  >
    <div class="grid gap-4">
      <label class="grid gap-1.5">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.META.TEST_CHANNEL') }}
        </span>
        <select
          v-model="channelId"
          class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1 text-n-slate-12"
          data-testid="flow-test-channel"
        >
          <option
            v-for="option in channelOptions"
            :key="option.value"
            :value="option.value"
          >
            {{ option.label }}
          </option>
        </select>
      </label>
      <Input
        v-model="phoneNumber"
        type="tel"
        :label="$t('WHATSAPP_FLOWS.META.TEST_NUMBER')"
        :placeholder="$t('WHATSAPP_FLOWS.META.TEST_NUMBER_PLACEHOLDER')"
        data-testid="flow-test-number"
      />
      <p
        class="flex items-start gap-2 p-3 m-0 text-xs rounded-lg bg-n-amber-3 text-n-amber-11"
        data-testid="flow-test-window"
      >
        <span class="i-lucide-clock size-4 shrink-0" aria-hidden="true" />
        {{ $t('WHATSAPP_FLOWS.META.TEST_WINDOW') }}
      </p>
      <p
        v-if="result?.ok"
        class="m-0 text-sm text-n-teal-11"
        role="status"
        data-testid="flow-test-success"
      >
        {{ $t('WHATSAPP_FLOWS.META.TEST_SENT', { number: result.text }) }}
      </p>
      <p
        v-else-if="result"
        class="m-0 text-sm text-n-ruby-11"
        role="alert"
        data-testid="flow-test-error"
      >
        {{ $t('WHATSAPP_FLOWS.META.TEST_FAILED') }}
        <span v-if="result.text">{{ result.text }}</span>
      </p>
    </div>
    <template #footer>
      <div class="flex items-center justify-end gap-3">
        <Button
          type="button"
          slate
          faded
          :label="$t('WHATSAPP_FLOWS.META.CLOSE')"
          data-testid="flow-test-close"
          @click="close"
        />
        <Button
          type="button"
          icon="i-lucide-send"
          :label="$t('WHATSAPP_FLOWS.META.TEST_SEND')"
          :is-loading="isSending"
          :disabled="!canSend"
          data-testid="flow-test-send"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
