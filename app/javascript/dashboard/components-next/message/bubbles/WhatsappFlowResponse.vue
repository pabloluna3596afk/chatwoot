<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import { copyTextToClipboard } from 'shared/helpers/clipboard';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import MessageMeta from '../MessageMeta.vue';
import BaseBubble from './Base.vue';
import { useMessageContext } from '../provider.js';
import {
  buildFlowResponseEntries,
  flowResponseToText,
} from '../helpers/whatsappFlowResponse.js';

const { contentAttributes, shouldGroupWithNext } = useMessageContext();
const { t } = useI18n();
const metadata = computed(
  () => contentAttributes.value?.whatsappFlowMeta ?? {}
);
const responseEntries = computed(() =>
  buildFlowResponseEntries(
    contentAttributes.value?.whatsappFlowResponse ?? {},
    metadata.value,
    t('CONVERSATION.WHATSAPP_FLOW_FILE_RECEIVED')
  )
);
const title = computed(() =>
  metadata.value.name
    ? `${t('CONVERSATION.WHATSAPP_FLOW_COMPLETED')} · ${metadata.value.name}`
    : t('CONVERSATION.WHATSAPP_FLOW_COMPLETED')
);

const copyData = async () => {
  try {
    await copyTextToClipboard(
      flowResponseToText(responseEntries.value, metadata.value.name)
    );
    useAlert(t('CONVERSATION.WHATSAPP_FLOW_COPIED'));
  } catch {
    useAlert(t('CONVERSATION.WHATSAPP_FLOW_COPY_ERROR'));
  }
};
</script>

<template>
  <BaseBubble
    hide-meta
    class="px-4 py-3 min-w-64 w-[32rem] max-w-full"
    data-bubble-name="whatsapp-flow-response"
  >
    <div class="flex items-center gap-3 pb-3">
      <span
        class="flex items-center justify-center size-8 shrink-0 rounded-lg bg-n-blue-3 text-n-blue-9"
      >
        <Icon icon="i-lucide-clipboard-check" class="size-4" />
      </span>
      <span class="font-medium break-words min-w-0">{{ title }}</span>
    </div>
    <dl class="border-y divide-y border-n-weak divide-n-weak">
      <div
        v-for="entry in responseEntries"
        :key="entry.key"
        class="grid grid-cols-[minmax(0,2fr)_minmax(0,5fr)] sm:grid-cols-[minmax(0,3fr)_minmax(0,7fr)] gap-3 py-2.5"
      >
        <dt class="text-xs text-n-slate-11 break-words pt-0.5">
          {{ entry.label }}
        </dt>
        <dd
          class="min-w-0 whitespace-pre-wrap break-words [overflow-wrap:anywhere]"
        >
          <div v-if="entry.chips?.length" class="flex flex-wrap gap-1.5">
            <span
              v-for="(chip, index) in entry.chips"
              :key="index"
              class="px-2 py-1 rounded-md bg-n-alpha-black2 text-xs max-w-full"
            >
              {{ chip }}
            </span>
          </div>
          <template v-else>{{ entry.value }}</template>
        </dd>
      </div>
    </dl>
    <div class="flex items-center justify-between gap-3 pt-3">
      <Button
        v-if="responseEntries.length"
        :label="t('CONVERSATION.WHATSAPP_FLOW_COPY')"
        icon="i-lucide-copy"
        color="blue"
        variant="faded"
        size="sm"
        data-testid="flow-response-copy"
        @click="copyData"
      />
      <MessageMeta
        v-if="!shouldGroupWithNext"
        class="text-n-slate-11 ms-auto"
      />
    </div>
  </BaseBubble>
</template>
