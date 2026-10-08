<script setup>
import { computed, nextTick, ref, watch } from 'vue';
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
const columns = ref(null);
const fields = ref(null);
const originalCta = computed(() =>
  t('WHATSAPP_TEMPLATES.SEND_CENTER.OPEN_FLOW')
);
const isModified = computed(
  () =>
    header.value !== '' ||
    body.value !== props.flow.name ||
    cta.value !== originalCta.value
);
const restore = () => {
  header.value = '';
  body.value = props.flow.name;
  cta.value = originalCta.value;
};
const openCustomization = async () => {
  customizing.value = true;
  await nextTick();
  fields.value.querySelector('input, textarea').focus({ preventScroll: true });
};
const closeCustomization = async () => {
  customizing.value = false;
  await nextTick();
  columns.value
    .querySelector('[data-testid="flow-send-customize"]')
    .focus({ preventScroll: true });
};
const handleEscape = event => {
  if (!customizing.value) return;
  event.preventDefault();
  event.stopPropagation();
  closeCustomization();
};
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
    restore();
  },
  { immediate: true }
);
const invalidReason = computed(() => {
  if (!body.value.trim())
    return t('WHATSAPP_TEMPLATES.SEND_CENTER.BODY_REQUIRED');
  if (!cta.value.trim())
    return t('WHATSAPP_TEMPLATES.SEND_CENTER.BUTTON_REQUIRED');
  if (buttonHasEmoji.value) return t('WHATSAPP_FLOWS.ERRORS.button_no_emoji');
  if (!isValid.value) return t('WHATSAPP_TEMPLATES.SEND_CENTER.TEXT_LIMITS');
  return '';
});
defineExpose({
  isValid,
  payload,
  customizing,
  closeCustomization,
  invalidReason,
});
</script>

<template>
  <div
    ref="columns"
    class="relative grid min-h-0 min-w-0 flex-1 items-start gap-6"
    :class="
      customizing
        ? 'grid-cols-[var(--phone-preview-width)] xl:grid-cols-[var(--phone-preview-width)_var(--send-center-unit)]'
        : 'grid-cols-[var(--phone-preview-width)]'
    "
    data-testid="flow-send-columns"
    @keydown.esc="handleEscape"
  >
    <div
      class="min-h-0 min-w-0 max-h-full overflow-y-auto overscroll-contain flex flex-col gap-3"
      data-testid="flow-send-preview-column"
    >
      <MessagePreview :header="header" :body="body" :buttons="[cta]" flow />
      <Button
        v-if="!customizing"
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
        @click="openCustomization"
      >
        <span>{{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZE') }}</span>
        <span
          v-if="isModified"
          class="size-2 shrink-0 rounded-full bg-n-teal-9"
          role="img"
          :aria-label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZED_MESSAGE')"
          :title="$t('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZED_MESSAGE')"
          data-testid="flow-send-modified-dot"
        />
      </Button>
    </div>
    <div
      v-if="customizing"
      id="flow-send-customization"
      ref="fields"
      role="region"
      aria-labelledby="flow-send-panel-title"
      class="grid min-h-0 min-w-0 max-h-full overflow-y-auto overscroll-contain gap-3 rounded-xl bg-n-solid-2 p-4 xl:-mt-11 xl:max-h-[calc(100%+2.75rem)] max-xl:absolute max-xl:top-0 max-xl:left-[calc(-1*var(--send-center-unit)-1.5rem)] max-xl:w-[var(--send-center-unit)] max-xl:z-10"
      data-testid="flow-send-fields-column"
    >
      <div class="flex flex-col gap-2" data-testid="flow-send-panel-header">
        <div class="flex items-center justify-between gap-2">
          <h3
            id="flow-send-panel-title"
            class="text-sm font-semibold text-n-slate-12"
          >
            {{ $t('WHATSAPP_TEMPLATES.SEND_CENTER.CUSTOMIZE') }}
          </h3>
          <Button
            type="button"
            ghost
            slate
            sm
            icon="i-lucide-x"
            :aria-label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.CLOSE_CUSTOMIZE')"
            :title="$t('WHATSAPP_TEMPLATES.SEND_CENTER.CLOSE_CUSTOMIZE')"
            data-testid="flow-send-close-customize"
            @click="closeCustomization"
          />
        </div>
        <Button
          type="button"
          ghost
          slate
          sm
          class="justify-self-start !w-fit !justify-start text-start !px-0 !text-xs"
          icon="i-lucide-rotate-ccw"
          :label="$t('WHATSAPP_TEMPLATES.SEND_CENTER.RESTORE')"
          :disabled="!isModified"
          data-testid="flow-send-restore"
          @click="restore"
        />
      </div>
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
    </div>
  </div>
</template>
