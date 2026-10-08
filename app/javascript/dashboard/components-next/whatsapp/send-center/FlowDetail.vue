<script setup>
import { computed, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import TextArea from 'dashboard/components-next/textarea/TextArea.vue';
import MessagePreview from './MessagePreview.vue';

const props = defineProps({ flow: { type: Object, required: true } });
const { t } = useI18n();
const customizing = ref(false);
const header = ref('');
const body = ref('');
const cta = ref('');
const LIMITS = { header: 60, body: 1024, cta: 20 };
const buttonHasEmoji = computed(() =>
  /[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}]|\uFE0F|\u20e3/u.test(cta.value)
);
const isValid = computed(
  () =>
    body.value.trim().length > 0 &&
    cta.value.trim().length > 0 &&
    header.value.length <= LIMITS.header &&
    body.value.length <= LIMITS.body &&
    cta.value.length <= LIMITS.cta &&
    !buttonHasEmoji.value
);
const payload = computed(() => ({
  whatsapp_flow_id: props.flow.id,
  header: header.value,
  body: body.value,
  cta: cta.value,
}));
watch(
  () => props.flow.id,
  () => {
    customizing.value = false;
    header.value = '';
    body.value = props.flow.name;
    cta.value = t('WHATSAPP_TEMPLATES.SEND_CENTER.OPEN_FLOW');
  },
  { immediate: true }
);
defineExpose({ isValid, payload });
</script>

<template>
  <div
    class="grid min-h-0 min-w-0 flex-1 items-start gap-4"
    :class="customizing ? 'grid-cols-2' : 'grid-cols-1'"
    data-testid="flow-send-columns"
  >
    <div
      class="min-h-0 min-w-0 max-h-full overflow-y-auto overscroll-contain flex flex-col gap-3"
      data-testid="flow-send-preview-column"
    >
      <MessagePreview :header="header" :body="body" :buttons="[cta]" flow />
      <Button
        class="w-full !h-auto whitespace-normal text-start"
        type="button"
        slate
        ghost
        sm
        icon="i-lucide-sliders-horizontal"
        :label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZE')"
        :aria-expanded="customizing"
        aria-controls="flow-send-customization"
        data-testid="flow-send-customize"
        @click="customizing = !customizing"
      />
    </div>
    <div
      v-if="customizing"
      id="flow-send-customization"
      class="grid min-h-0 min-w-0 max-h-full overflow-y-auto overscroll-contain gap-3 rounded-xl bg-n-alpha-1 p-4"
      data-testid="flow-send-fields-column"
    >
      <Input
        v-model="header"
        :label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.HEADER')"
        :maxlength="LIMITS.header"
        data-testid="flow-send-header"
      />
      <TextArea
        v-model="body"
        :label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.BODY')"
        :max-length="LIMITS.body"
        show-character-count
        data-testid="flow-send-body"
      />
      <Input
        v-model="cta"
        :label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.BUTTON_TEXT')"
        :maxlength="LIMITS.cta"
        data-testid="flow-send-cta"
      />
      <p v-if="buttonHasEmoji" role="alert" class="text-xs text-n-ruby-11">
        {{ $t('WHATSAPP_FLOWS.ERRORS.button_no_emoji') }}
      </p>
    </div>
  </div>
</template>
