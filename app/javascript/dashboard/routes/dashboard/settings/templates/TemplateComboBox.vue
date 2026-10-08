<script setup>
import { provide, ref } from 'vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({ showCreateAttribute: { type: Boolean, default: false } });
const emit = defineEmits(['createAttribute']);
defineOptions({ inheritAttrs: false });
const portal = ref(null);
// Keep the shared dropdown in the panel's scroll area, above its fixed footer.
provide('dialogPortalTarget', portal);
</script>

<template>
  <div class="w-full min-w-0">
    <ComboBox v-bind="$attrs" teleport>
      <template v-if="showCreateAttribute" #footer="{ close }">
        <Button
          type="button"
          ghost
          slate
          sm
          class="w-full justify-start"
          icon="i-lucide-plus"
          :label="$t('WHATSAPP_TEMPLATE_MGMT.FORM.CREATE_ATTRIBUTE')"
          data-testid="copy-create-attribute"
          @click="
            close();
            emit('createAttribute');
          "
        />
      </template>
    </ComboBox>
    <div
      ref="portal"
      data-template-picker-portal
      class="[&>[data-combobox-dropdown]]:!static [&>[data-combobox-dropdown]]:!mt-2 [&>[data-combobox-dropdown]]:!w-full [&>[data-combobox-dropdown]]:!max-h-80"
    />
  </div>
</template>
