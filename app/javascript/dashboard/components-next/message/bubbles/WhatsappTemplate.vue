<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import AttachmentChips from '../chips/AttachmentChips.vue';
import FormattedContent from './Text/FormattedContent.vue';
import { useMessageContext } from '../provider.js';

const { content, contentAttributes, additionalAttributes, attachments } =
  useMessageContext();
const template = computed(
  () =>
    contentAttributes.value.whatsappTemplate ??
    additionalAttributes.value.templateParams
);
const buttons = computed(
  () => template.value.buttons ?? contentAttributes.value.templateButtons ?? []
);
const { t } = useI18n();
const category = computed(() => {
  const labels = {
    UTILITY: t('CONVERSATION.WHATSAPP_TEMPLATE_CATEGORIES.UTILITY'),
    MARKETING: t('CONVERSATION.WHATSAPP_TEMPLATE_CATEGORIES.MARKETING'),
    AUTHENTICATION: t(
      'CONVERSATION.WHATSAPP_TEMPLATE_CATEGORIES.AUTHENTICATION'
    ),
  };
  return labels[template.value.category] ?? null;
});
const imageHeader = computed(() =>
  template.value.header?.format === 'IMAGE'
    ? attachments.value?.find(attachment => attachment.fileType === 'image')
    : null
);
const remainingAttachments = computed(
  () =>
    attachments.value?.filter(attachment => attachment !== imageHeader.value) ??
    []
);
const buttonIcon = type => {
  if (type === 'URL') return 'i-lucide-external-link';
  if (type === 'FLOW') return 'i-lucide-workflow';
  if (type === 'PHONE_NUMBER') return 'i-lucide-phone';
  if (type === 'COPY_CODE') return 'i-lucide-copy';
  return 'i-lucide-reply';
};
</script>

<template>
  <BaseBubble
    class="px-4 py-3 w-[29rem] max-w-full"
    data-bubble-name="whatsapp-template"
  >
    <div class="flex items-center gap-2.5 pb-3 border-b border-n-weak">
      <span
        class="flex items-center justify-center size-8 shrink-0 rounded-lg bg-n-solid-1 text-n-blue-9"
      >
        <Icon icon="i-lucide-panels-top-left" class="size-4" />
      </span>
      <span class="font-medium min-w-0 break-words">{{
        $t('CONVERSATION.WHATSAPP_TEMPLATE_SENT', { name: template.name })
      }}</span>
      <span
        v-if="category"
        class="ms-auto shrink-0 px-2 py-1 rounded-md bg-n-solid-1 text-[0.625rem] font-medium text-n-slate-12"
      >
        {{ category }}
      </span>
    </div>
    <div class="flex flex-col gap-1.5 py-3">
      <img
        v-if="imageHeader"
        :src="imageHeader.dataUrl"
        :alt="template.header.text || ''"
        class="w-full max-h-56 object-cover rounded-lg mb-2"
      />
      <span
        v-if="template.header?.text"
        class="font-semibold whitespace-pre-wrap break-words"
        >{{ template.header.text }}</span
      >
      <FormattedContent v-if="content" :content="content" />
      <span
        v-if="template.footer"
        class="text-xs text-n-slate-11 whitespace-pre-wrap break-words"
        >{{ template.footer }}</span
      >
      <AttachmentChips :attachments="remainingAttachments" class="gap-2" />
    </div>
    <div v-if="buttons.length" class="border-t border-n-weak">
      <div
        v-for="(button, index) in buttons"
        :key="index"
        class="flex items-center justify-center gap-2 py-2 text-n-blue-9"
      >
        <Icon :icon="buttonIcon(button.type)" class="size-4 shrink-0" />
        <span class="break-words">{{ button.text }}</span>
      </div>
    </div>
  </BaseBubble>
</template>
