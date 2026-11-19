<script setup>
import { ref, computed } from 'vue';
import BaseBubble from './Base.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { useMediaState } from '../media/useMediaState';
import { ATTACHMENT_TYPES } from '../constants';

const emit = defineEmits(['error']);
const showGallery = ref(false);
const { filteredCurrentChatAttachments, attachments, channelType } =
  useMessageContext();

const attachment = computed(() => {
  return attachments.value[0];
});

const { hasError, errorText, onError } = useMediaState(attachment, channelType);
const handleError = () => {
  onError();
  emit('error');
};

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="!hasError && (showGallery = true)"
  >
    <div
      v-if="hasError"
      role="status"
      class="flex gap-2 p-3 text-xs text-n-slate-11"
    >
      <Icon icon="i-lucide-image-off" />{{ errorText }}
    </div>
    <div v-else class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      <video
        controls
        class="rounded-lg skip-context-menu"
        :src="attachment.dataUrl"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @click.stop
        @error="handleError"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>
