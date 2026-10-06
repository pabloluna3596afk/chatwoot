<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';

const props = defineProps({
  flows: { type: Array, default: () => [] },
  canReply: { type: Boolean, required: true },
  send: { type: Function, required: true },
});
const { t } = useI18n();
const dialog = ref(null);
const flowId = ref(null);
const header = ref('');
const body = ref('');
const cta = ref(t('WHATSAPP_FLOWS.SEND.OPEN'));
const isSending = ref(false);
const error = ref('');
const canSend = computed(
  () =>
    props.canReply &&
    flowId.value &&
    body.value.trim() &&
    cta.value.trim() &&
    !isSending.value
);
watch(
  () => props.flows,
  flows => {
    flowId.value = flows[0]?.id ?? null;
  },
  { immediate: true }
);
watch(
  flowId,
  id => {
    body.value = props.flows.find(flow => flow.id === id)?.name || '';
  },
  { immediate: true }
);
const close = () => dialog.value.close();
const open = () => {
  error.value = '';
  dialog.value.open();
};
const submit = async () => {
  if (!canSend.value) return;
  isSending.value = true;
  error.value = '';
  try {
    await props.send({
      whatsapp_flow_id: flowId.value,
      header: header.value,
      body: body.value,
      cta: cta.value,
    });
    close();
  } catch (e) {
    error.value = e.response?.data?.error || e.message;
  } finally {
    isSending.value = false;
  }
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="md"
    :title="$t('WHATSAPP_FLOWS.SEND.TITLE')"
    :description="$t('WHATSAPP_FLOWS.SEND.DESCRIPTION')"
  >
    <div class="grid gap-4">
      <label class="grid gap-1.5 text-sm text-n-slate-12">
        {{ $t('WHATSAPP_FLOWS.SEND.FLOW') }}
        <select
          v-model="flowId"
          class="h-8 px-2 text-sm border rounded-lg border-n-weak bg-n-solid-1"
          data-testid="flow-send-choice"
        >
          <option v-for="flow in flows" :key="flow.id" :value="flow.id">
            {{ flow.name }}
          </option>
        </select>
      </label>
      <p v-if="!flows.length" class="text-sm text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.SEND.EMPTY') }}
      </p>
      <Input
        v-model="header"
        :label="$t('WHATSAPP_FLOWS.SEND.HEADER')"
        :max-length="60"
      />
      <TextArea
        v-model="body"
        :label="$t('WHATSAPP_FLOWS.SEND.BODY')"
        :max-length="1024"
        data-testid="flow-send-body"
      />
      <Input
        v-model="cta"
        :label="$t('WHATSAPP_FLOWS.SEND.CTA')"
        :max-length="20"
      />
      <p
        v-if="!canReply"
        class="p-3 m-0 text-sm rounded-lg bg-n-amber-3 text-n-amber-11"
        data-testid="flow-send-window"
      >
        {{ $t('WHATSAPP_FLOWS.SEND.OUTSIDE_WINDOW') }}
      </p>
      <p v-if="error" role="alert" class="text-sm text-n-ruby-11">
        {{ error }}
      </p>
    </div>
    <template #footer>
      <div class="flex justify-end gap-3">
        <Button
          slate
          faded
          :label="$t('WHATSAPP_FLOWS.META.CLOSE')"
          @click="close"
        />
        <Button
          :label="$t('WHATSAPP_FLOWS.SEND.TITLE')"
          :disabled="!canSend"
          :is-loading="isSending"
          data-testid="flow-send-submit"
          @click="submit"
        />
      </div>
    </template>
  </Dialog>
</template>
