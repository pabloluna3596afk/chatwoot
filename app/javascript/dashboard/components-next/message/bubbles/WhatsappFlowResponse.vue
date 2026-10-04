<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';
import {
  buildFlowResponseEntries,
  flowResponseToText,
} from '../helpers/whatsappFlowResponse.js';

const { content, contentAttributes } = useMessageContext();
const { t } = useI18n();

const responseEntries = computed(() => {
  const response =
    contentAttributes.value?.whatsappFlowResponse?.responseJson ?? {};

  return buildFlowResponseEntries(response);
});

// The text of the message lists the same answers as bullets; the card shows them as rows, so it keeps only a title.
const title = computed(() =>
  responseEntries.value.length
    ? t('CONVERSATION.WHATSAPP_FLOW_COMPLETED')
    : content.value || t('CONVERSATION.WHATSAPP_FLOW_RESPONSE')
);

const copyData = async () => {
  try {
    await copyTextToClipboard(flowResponseToText(responseEntries.value));
    useAlert(t('CONVERSATION.WHATSAPP_FLOW_COPIED'));
  } catch {
    useAlert(t('CONVERSATION.WHATSAPP_FLOW_COPY_ERROR'));
  }
};
</script>

<template>
  <BaseBubble
    class="px-4 py-3 min-w-64 max-w-lg"
    data-bubble-name="whatsapp-flow-response"
  >
    <div class="flex items-center justify-between gap-3">
      <div class="flex items-center gap-2 font-medium">
        <span class="i-lucide-clipboard-check size-4 shrink-0" />
        {{ title }}
      </div>
      <Button
        v-if="responseEntries.length"
        :label="t('CONVERSATION.WHATSAPP_FLOW_COPY')"
        icon="i-lucide-copy"
        color="slate"
        variant="faded"
        size="xs"
        data-testid="flow-response-copy"
        @click="copyData"
      />
    </div>
    <dl
      v-if="responseEntries.length"
      class="mt-3 overflow-hidden border divide-y rounded-lg border-n-weak divide-n-weak"
    >
      <div
        v-for="entry in responseEntries"
        :key="entry.key"
        class="grid gap-0.5 px-3 py-2 sm:grid-cols-[minmax(0,2fr)_minmax(0,3fr)] sm:gap-3"
      >
        <dt class="text-xs text-n-slate-11">
          {{ entry.label }}
        </dt>
        <dd class="whitespace-pre-wrap break-words">
          {{ entry.value }}
        </dd>
      </div>
    </dl>
  </BaseBubble>
</template>
