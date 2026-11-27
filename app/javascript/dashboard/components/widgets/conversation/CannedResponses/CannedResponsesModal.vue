<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import CannedResponsesPicker from './CannedResponsesPicker.vue';

const props = defineProps({
  variables: { type: Object, default: () => ({}) },
  show: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['onSelect', 'cancel', 'update:show']);

const { t } = useI18n();

const localShow = computed({
  get: () => props.show,
  set: value => emit('update:show', value),
});

const onSelect = item => {
  emit('onSelect', item);
};

const onClose = () => {
  emit('cancel');
};
</script>

<template>
  <woot-modal
    v-model:show="localShow"
    :on-close="onClose"
    size="modal-big"
    class="!h-[var(--app-height,100dvh)] !top-[var(--app-offset-top,0px)] p-2 [&>.modal-container]:flex [&>.modal-container]:flex-col [&>.modal-container>button]:min-h-11 [&>.modal-container>button]:min-w-11"
  >
    <woot-modal-header
      :header-title="t('CANNED_MGMT.PICKER.TITLE')"
      :header-content="t('CANNED_MGMT.PICKER.SUBTITLE')"
    />
    <div class="flex min-h-0 max-h-[60dvh] px-4 py-4 sm:px-8 sm:py-6">
      <CannedResponsesPicker :variables="variables" @on-select="onSelect" />
    </div>
  </woot-modal>
</template>
