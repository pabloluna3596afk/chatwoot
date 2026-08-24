<script setup>
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import { tintStylesFromHex } from 'dashboard/helper/colorHelper';

defineProps({
  option: {
    type: Object,
    default: () => {},
  },
  variant: {
    type: String,
    default: 'default',
  },
});
</script>

<template>
  <div class="menu group text-n-slate-12 min-h-7 min-w-0" role="button">
    <fluent-icon
      v-if="variant === 'icon' && option.icon"
      :icon="option.icon"
      size="14"
      class="flex-shrink-0"
    />
    <span
      v-if="
        (variant === 'label' || variant === 'label-assigned') && option.color
      "
      class="inline-flex items-center flex-shrink-0 max-w-[9rem] truncate rounded-md border border-solid px-1.5 py-0.5 text-xxs font-medium"
      :style="tintStylesFromHex(option.color)"
    >
      {{ option.label }}
    </span>
    <Avatar
      v-if="variant === 'agent'"
      :name="option.label"
      :src="option.thumbnail"
      :icon-name="option.iconName"
      :status="option.status === 'online' ? option.status : null"
      :size="20"
      class="flex-shrink-0"
    >
      <template v-if="option.iconName && option.thumbnail" #badge>
        <div
          class="absolute z-20 flex items-center justify-center rounded-full outline outline-1 outline-n-weak bg-n-solid-1 -bottom-0.5 ltr:-right-0.5 rtl:-left-0.5 size-3"
        >
          <Icon icon="i-lucide-bot" class="text-n-slate-11 size-2" />
        </div>
      </template>
    </Avatar>
    <p
      v-if="variant !== 'label' && variant !== 'label-assigned'"
      class="menu-label truncate min-w-0 flex-1"
    >
      {{ option.label }}
    </p>
    <span v-else class="flex-1 min-w-0" />
    <Icon
      v-if="variant === 'label-assigned'"
      icon="i-lucide-check"
      class="flex-shrink-0 size-3.5 text-n-brand group-hover:text-white"
    />
  </div>
</template>

<style scoped lang="scss">
.menu {
  width: calc(6.25rem * 2);
  @apply flex items-center flex-nowrap p-1 rounded-md overflow-hidden cursor-pointer;

  .menu-label {
    @apply my-0 mx-2 text-xs flex-shrink-0;
  }

  &:hover {
    @apply bg-n-brand text-white;
  }
}

.agent-thumbnail {
  margin-top: 0 !important;
}
</style>
