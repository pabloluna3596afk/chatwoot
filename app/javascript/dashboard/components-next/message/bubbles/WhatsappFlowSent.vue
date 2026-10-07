<script setup>
import { computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import FormattedContent from './Text/FormattedContent.vue';
import { useMessageContext } from '../provider.js';

const { content, additionalAttributes } = useMessageContext();
const flow = computed(() => additionalAttributes.value.whatsappFlow);
</script>

<template>
  <BaseBubble
    class="px-4 py-3 w-[29rem] max-w-full"
    data-bubble-name="whatsapp-flow-sent"
  >
    <div class="flex items-center gap-2.5 pb-3 border-b border-n-weak">
      <span
        class="flex items-center justify-center size-8 shrink-0 rounded-lg bg-n-solid-1 text-n-blue-9"
      >
        <Icon icon="i-lucide-workflow" class="size-4" />
      </span>
      <span class="font-medium min-w-0 break-words">{{
        $t('CONVERSATION.WHATSAPP_FLOW_SENT', { name: flow.name })
      }}</span>
    </div>
    <div class="flex flex-col gap-1.5 py-3">
      <span
        v-if="flow.header"
        class="font-semibold whitespace-pre-wrap break-words"
        >{{ flow.header }}</span
      >
      <FormattedContent
        v-if="content || flow.body"
        :content="content || flow.body"
      />
    </div>
    <div
      v-if="flow.cta"
      class="flex items-center justify-center gap-2 py-2 border-t border-n-weak text-n-blue-9"
    >
      <Icon icon="i-lucide-workflow" class="size-4" />
      <span class="break-words">{{ flow.cta }}</span>
    </div>
  </BaseBubble>
</template>
