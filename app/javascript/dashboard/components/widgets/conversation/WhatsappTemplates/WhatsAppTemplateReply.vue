<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

defineProps({
  template: {
    type: Object,
    default: () => ({}),
  },
  sendRenderedContent: {
    type: Boolean,
    default: false,
  },
  inboxId: {
    type: Number,
    default: null,
  },
});

const emit = defineEmits(['sendMessage', 'resetTemplate']);

// The variables start with the CRM value their name stands for, resolved for this conversation.
const { defaultValues } = useTemplateBindings('message');
const chat = useMapGetter('getSelectedChat');
const currentUser = useMapGetter('getCurrentUser');
const resolveContext = computed(() => ({
  contact: chat.value?.meta?.sender,
  conversation: chat.value,
  agent: currentUser.value,
}));

const handleSendMessage = payload => {
  emit('sendMessage', payload);
};

const handleResetTemplate = () => {
  emit('resetTemplate');
};
</script>

<template>
  <div class="w-full">
    <WhatsAppTemplateParser
      :template="template"
      :send-rendered-content="sendRenderedContent"
      :media-inbox-id="inboxId"
      :default-values="defaultValues"
      :resolve-context="resolveContext"
      @send-message="handleSendMessage"
      @reset-template="handleResetTemplate"
    >
      <template #actions="{ sendMessage, resetTemplate, disabled }">
        <footer class="flex gap-2 justify-end">
          <NextButton
            faded
            slate
            type="reset"
            :label="$t('WHATSAPP_TEMPLATES.PARSER.GO_BACK_LABEL')"
            @click="resetTemplate"
          />
          <NextButton
            type="button"
            :label="$t('WHATSAPP_TEMPLATES.PARSER.SEND_MESSAGE_LABEL')"
            :disabled="disabled"
            @click="sendMessage"
          />
        </footer>
      </template>
    </WhatsAppTemplateParser>
  </div>
</template>
