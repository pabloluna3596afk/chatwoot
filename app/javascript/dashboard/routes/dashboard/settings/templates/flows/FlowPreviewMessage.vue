<script setup>
// Reuse the exact chat bubbles with a local message context; never create a message.
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { provideMessageContext } from 'dashboard/components-next/message/provider';
import WhatsappFlowResponse from 'dashboard/components-next/message/bubbles/WhatsappFlowResponse.vue';
import WhatsappFlowSent from 'dashboard/components-next/message/bubbles/WhatsappFlowSent.vue';
import { answerBlocks } from 'shared/helpers/flowAnswers';

const props = defineProps({
  kind: {
    type: String,
    required: true,
    validator: value => ['sent', 'response'].includes(value),
  },
  flowName: { type: String, required: true },
  definition: { type: Object, required: true },
  answers: { type: Object, required: true },
});
const { t } = useI18n();
const contentAttributes = computed(() => ({
  whatsappFlowResponse: props.answers,
  whatsappFlowMeta: {
    name: props.flowName,
    fields: answerBlocks(props.definition).map(block => ({
      key: block.key,
      label: block.label,
      type: block.type,
      options:
        block.type === 'optin'
          ? [
              { id: true, title: t('WHATSAPP_FLOWS.SIMULATOR.YES') },
              { id: false, title: t('WHATSAPP_FLOWS.SIMULATOR.NO') },
            ]
          : block.options,
    })),
  },
}));
provideMessageContext({
  content: computed(() => props.flowName),
  contentAttributes,
  additionalAttributes: computed(() => ({
    whatsappFlow: {
      name: props.flowName,
      header: props.flowName,
      body: props.flowName,
      cta: t('WHATSAPP_FLOWS.SIMULATOR.OPEN_FLOW'),
    },
  })),
  shouldGroupWithNext: ref(true),
  variant: computed(() => (props.kind === 'sent' ? 'agent' : 'user')),
  orientation: computed(() => (props.kind === 'sent' ? 'right' : 'left')),
});
</script>

<template>
  <WhatsappFlowSent
    v-if="kind === 'sent'"
    class="!w-full !max-w-full !min-w-0"
  />
  <WhatsappFlowResponse v-else class="!w-full !max-w-full !min-w-0" />
</template>
