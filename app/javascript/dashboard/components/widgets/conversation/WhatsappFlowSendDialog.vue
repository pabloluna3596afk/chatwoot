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
const customizing = ref(false);
const LIMITS = { header: 60, body: 1024, cta: 20 };
const buttonHasEmoji = computed(() =>
  /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]|\uFE0F|\u20e3/u.test(cta.value)
);
const error = ref('');
const canSend = computed(
  () =>
    props.canReply &&
    flowId.value &&
    body.value.trim() &&
    cta.value.trim() &&
    header.value.length <= LIMITS.header &&
    body.value.length <= LIMITS.body &&
    cta.value.length <= LIMITS.cta &&
    !buttonHasEmoji.value &&
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
  customizing.value = false;
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
    :width="customizing ? '2xl' : 'lg'"
    body-scroll
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
        {{ $t('WHATSAPP_FLOWS.SEND.REPUBLISH_HINT') }}
      </p>
      <button
        v-if="flows.length"
        type="button"
        class="flex items-center gap-2 text-sm text-n-blue-text text-start"
        :aria-expanded="customizing"
        aria-controls="flow-send-customization"
        data-testid="flow-send-customize"
        @click="customizing = !customizing"
      >
        <span
          :class="customizing ? 'i-lucide-chevron-up' : 'i-lucide-chevron-down'"
          class="size-4"
        />
        {{ $t('WHATSAPP_FLOWS.SEND.CUSTOMIZE') }}
      </button>
      <div
        v-if="flows.length"
        class="grid gap-4"
        :class="customizing ? 'sm:grid-cols-2' : ''"
      >
        <div v-if="customizing" id="flow-send-customization" class="grid gap-3">
          <Input
            v-model="header"
            :label="$t('WHATSAPP_FLOWS.SEND.HEADER')"
            :maxlength="LIMITS.header"
            data-testid="flow-send-header"
          />
          <TextArea
            v-model="body"
            :label="$t('WHATSAPP_FLOWS.SEND.BODY')"
            :max-length="LIMITS.body"
            show-character-count
            data-testid="flow-send-body"
          />
          <Input
            v-model="cta"
            :label="$t('WHATSAPP_FLOWS.SEND.CTA')"
            :maxlength="LIMITS.cta"
            data-testid="flow-send-cta"
          />
          <p
            v-if="buttonHasEmoji"
            role="alert"
            class="m-0 text-xs text-n-ruby-11"
          >
            {{ $t('WHATSAPP_FLOWS.ERRORS.button_no_emoji') }}
          </p>
        </div>
        <div class="self-start p-4 rounded-xl bg-n-alpha-2">
          <p class="mb-2 text-xs text-n-slate-11">
            {{ $t('WHATSAPP_FLOWS.SEND.PREVIEW') }}
          </p>
          <div
            class="max-w-sm overflow-hidden rounded-lg shadow-sm bg-n-solid-1 text-n-slate-12"
            data-testid="flow-send-preview"
          >
            <div class="grid gap-1 p-3">
              <strong v-if="header" class="text-sm break-words">{{
                header
              }}</strong>
              <p class="m-0 text-sm whitespace-pre-wrap break-words">
                {{ body }}
              </p>
            </div>
            <div
              class="flex items-center justify-center gap-2 p-3 text-sm border-t border-n-weak text-n-teal-11"
            >
              <span class="i-lucide-file-text size-4" aria-hidden="true" />{{
                cta
              }}
            </div>
          </div>
        </div>
      </div>
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
