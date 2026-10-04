<script setup>
import { computed } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useTemplateBindings } from 'dashboard/composables/useTemplateBindings';
import WhatsAppTemplateParser from 'dashboard/components-next/whatsapp/WhatsAppTemplateParser.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import { useI18n } from 'vue-i18n';

const props = defineProps({
  template: {
    type: Object,
    default: () => ({}),
  },
  inboxId: {
    type: Number,
    default: null,
  },
  // The contact the conversation is started with, to fill the variables in.
  contact: {
    type: Object,
    default: null,
  },
});

const emit = defineEmits(['sendMessage', 'back']);
const { defaultValues } = useTemplateBindings('message');
const currentUser = useMapGetter('getCurrentUser');
const resolveContext = computed(() => ({
  contact: props.contact,
  agent: currentUser.value,
}));

const { t } = useI18n();

const handleSendMessage = payload => {
  emit('sendMessage', payload);
};

const handleBack = () => {
  emit('back');
};
</script>

<template>
  <div class="flex flex-col gap-4 px-4 pt-6 pb-5 items-start w-[28.75rem]">
    <div class="w-full">
      <WhatsAppTemplateParser
        :template="template"
        :media-inbox-id="inboxId"
        :default-values="defaultValues"
        :resolve-context="resolveContext"
        @send-message="handleSendMessage"
        @back="handleBack"
      >
        <template #actions="{ sendMessage, goBack, disabled }">
          <div class="flex gap-3 justify-between items-end w-full h-14">
            <Button
              :label="
                t(
                  'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.TEMPLATE_PARSER.BACK'
                )
              "
              color="slate"
              variant="faded"
              class="w-full font-medium"
              @click="goBack"
            />
            <Button
              :label="
                t(
                  'COMPOSE_NEW_CONVERSATION.FORM.WHATSAPP_OPTIONS.TEMPLATE_PARSER.SEND_MESSAGE'
                )
              "
              class="w-full font-medium"
              :disabled="disabled"
              @click="sendMessage"
            />
          </div>
        </template>
      </WhatsAppTemplateParser>
    </div>
  </div>
</template>
