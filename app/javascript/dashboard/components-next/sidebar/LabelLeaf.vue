<script setup>
import { computed } from 'vue';
import { tintStylesFromHex } from 'dashboard/helper/colorHelper';
import SidebarUnreadBadge from './SidebarUnreadBadge.vue';

const props = defineProps({
  label: { type: String, required: true },
  color: { type: String, default: '' },
  // eslint-disable-next-line vue/no-unused-properties
  active: { type: Boolean, default: false },
  badgeCount: { type: [Number, String], default: 0 },
});

const tintStyles = computed(() => tintStylesFromHex(props.color));
</script>

<template>
  <div class="flex min-w-0 flex-1 items-center gap-2">
    <span
      class="inline-flex w-fit max-w-full shrink-0 items-center rounded-md border px-1.5 py-0.5 text-xxs font-medium"
      :style="tintStyles"
    >
      <span class="truncate">{{ label }}</span>
    </span>
    <SidebarUnreadBadge
      class="shrink-0 ltr:ml-auto rtl:mr-auto"
      :count="badgeCount"
    />
  </div>
</template>
