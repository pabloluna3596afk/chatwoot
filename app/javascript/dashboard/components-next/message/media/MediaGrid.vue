<script setup>
import { computed, shallowRef } from 'vue';
import { useMessageContext } from '../provider';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import MediaTile from './MediaTile.vue';

const props = defineProps({
  items: { type: Array, required: true },
  caption: { type: String, default: '' },
});

const emit = defineEmits(['error']);

defineOptions({ inheritAttrs: false });

const { filteredCurrentChatAttachments, channelType, contentType } =
  useMessageContext();
const selected = shallowRef(null);
const visibleItems = computed(() => props.items.slice(0, 4));
</script>

<template>
  <div
    v-if="items.length"
    v-bind="$attrs"
    class="max-w-full min-w-0"
    :class="
      items.length > 1
        ? 'w-[20rem] grid grid-cols-2 gap-0.5 overflow-hidden rounded-lg'
        : 'w-fit'
    "
  >
    <MediaTile
      v-for="(item, index) in visibleItems"
      :key="item.id"
      :attachment="item"
      :caption="caption"
      :index="index"
      :total="items.length"
      :more="index === 3 ? Math.max(0, items.length - 4) : 0"
      :channel-type="channelType"
      :transparent="contentType === 'sticker'"
      @error="emit('error')"
      @open="selected = $event"
    />
  </div>
  <GalleryView
    v-if="selected"
    show
    :attachment="useSnakeCase(selected)"
    :all-attachments="filteredCurrentChatAttachments"
    @close="selected = null"
  />
</template>
