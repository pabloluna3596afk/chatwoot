<script setup>
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import Button from 'dashboard/components-next/button/Button.vue';

defineProps({ showCreateAttribute: { type: Boolean, default: false } });
const emit = defineEmits(['createAttribute']);
defineOptions({ inheritAttrs: false });
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
  </div>
</template>
