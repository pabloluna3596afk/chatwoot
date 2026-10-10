<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import SidePanel from 'dashboard/components-next/side-panel/SidePanel.vue';
import FlowPhoneSimulator from './FlowPhoneSimulator.vue';

// Clicking a Flow in the list shows it here, ready to try in the phone (the same simulator as the editor's
// Probar). Editing is one button away; the row click no longer jumps straight into the editor.
const emit = defineEmits(['edit']);
const { t } = useI18n();
const attributes = useMapGetter('attributes/getAttributes');
const panelRef = ref(null);
const summary = ref(null);
const flow = ref(null);
const loading = ref(false);
const failed = ref(false);
let requestId = 0;

const open = async row => {
  summary.value = row;
  flow.value = null;
  failed.value = false;
  loading.value = true;
  requestId += 1;
  const current = requestId;
  panelRef.value?.open();
  try {
    const { data } = await WhatsappFlowsAPI.show(row.id);
    if (current === requestId) flow.value = data;
  } catch {
    if (current === requestId) failed.value = true;
  } finally {
    if (current === requestId) loading.value = false;
  }
};
const close = () => panelRef.value?.close();
const edit = () => {
  emit('edit', summary.value);
  close();
};
const simulatorKey = computed(() => `${flow.value?.id}-${loading.value}`);

defineExpose({ open, close });
</script>

<template>
  <SidePanel
    ref="panelRef"
    width="md"
    :title="summary?.name || ''"
    :description="t('WHATSAPP_FLOWS.LIST.PREVIEW_DESCRIPTION')"
  >
    <p v-if="loading" class="text-sm text-n-slate-11" role="status">
      {{ t('WHATSAPP_FLOWS.LIST.PREVIEW_LOADING') }}
    </p>
    <p
      v-else-if="failed"
      class="text-sm text-n-ruby-11"
      role="alert"
      data-testid="flow-preview-error"
    >
      {{ t('WHATSAPP_FLOWS.LIST.LOAD_ERROR') }}
    </p>
    <div
      v-else-if="flow"
      class="flex justify-center [--phone-height:min(46.25rem,calc(100dvh_-_17.5rem))]"
      data-testid="flow-preview"
    >
      <FlowPhoneSimulator
        :key="simulatorKey"
        :definition="flow.definition"
        :flow-name="flow.name"
        :attributes="attributes"
        @edit="edit"
      />
    </div>
    <template #footer>
      <Button
        class="w-full"
        icon="i-lucide-pencil"
        :label="t('WHATSAPP_FLOWS.LIST.EDIT')"
        :disabled="!summary"
        data-testid="flow-preview-edit-button"
        @click="edit"
      />
    </template>
  </SidePanel>
</template>
