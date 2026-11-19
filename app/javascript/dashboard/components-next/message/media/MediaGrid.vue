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
const { filteredCurrentChatAttachments, channelType } = useMessageContext();
const selected = shallowRef(null);
const visibleItems = computed(() => props.items.slice(0, 4));
</script>

<template>
  <div
    v-if="items.length"
    class="max-w-[20rem] w-full min-w-0"
    :class="
      items.length > 1
        ? 'grid grid-cols-2 gap-0.5 overflow-hidden rounded-lg'
        : ''
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
