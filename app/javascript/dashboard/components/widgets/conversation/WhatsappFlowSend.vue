<script setup>
import { ref } from 'vue';
import { useAlert } from 'dashboard/composables';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import WhatsappFlowSendDialog from './WhatsappFlowSendDialog.vue';

const props = defineProps({
  conversationId: { type: Number, required: true },
  canReply: { type: Boolean, required: true },
});
const dialog = ref(null);
const flows = ref([]);
const isLoading = ref(false);
const open = async () => {
  isLoading.value = true;
  try {
    const { data } = await WhatsappFlowsAPI.conversationFlows(
      props.conversationId
    );
    flows.value = data.payload;
    dialog.value.open();
  } catch (error) {
    useAlert(error.response?.data?.error || error.message);
  } finally {
    isLoading.value = false;
  }
};
const send = payload =>
  WhatsappFlowsAPI.sendToConversation(props.conversationId, payload);
</script>

<template>
  <div class="px-3 pb-2">
    <Button
      ghost
      slate
      sm
      icon="i-lucide-send"
      :label="$t('WHATSAPP_FLOWS.SEND.TITLE')"
      :is-loading="isLoading"
      :disabled="!canReply"
      :title="!canReply ? $t('WHATSAPP_FLOWS.SEND.OUTSIDE_WINDOW') : ''"
      @click="open"
    />
    <p v-if="!canReply" class="m-0 text-xs text-n-slate-11">
      {{ $t('WHATSAPP_FLOWS.SEND.OUTSIDE_WINDOW') }}
    </p>
    <WhatsappFlowSendDialog
      ref="dialog"
      :flows="flows"
      :can-reply="canReply"
      :send="send"
    />
  </div>
</template>
