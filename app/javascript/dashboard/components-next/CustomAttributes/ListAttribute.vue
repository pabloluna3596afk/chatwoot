<script setup>
import { computed, ref, watch } from 'vue';

import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  attribute: {
    type: Object,
    required: true,
  },
  readOnly: {
    type: Boolean,
    default: false,
  },
});

const emit = defineEmits(['update', 'focusChange']);

const showAttributeListDropdown = ref(false);
watch(showAttributeListDropdown, open => emit('focusChange', open), {
  flush: 'sync',
});

const attributeListMenuItems = computed(() => {
  return (
    props.attribute.attributeValues?.map(value => ({
      label: value,
      value,
      action: 'select',
      isSelected: value === props.attribute.value,
    })) || []
  );
});

const closeDropdown = () => {
  showAttributeListDropdown.value = false;
};

const openDropdown = () => {
  if (props.readOnly) return;
  if (showAttributeListDropdown.value) {
    closeDropdown();
    return;
  }
  showAttributeListDropdown.value = true;
};

const handleAttributeAction = async action => {
  emit('update', action.value);
  closeDropdown();
};
</script>

<template>
  <MenuPopover
    v-model:open="showAttributeListDropdown"
    :menu-items="attributeListMenuItems"
    :label="attribute.attributeDisplayName"
    show-search
    align="start"
    panel-class="w-48 max-w-[calc(100vw-2rem)]"
    @action="handleAttributeAction"
  >
    <template #trigger>
      <button
        type="button"
        :disabled="readOnly"
        aria-haspopup="menu"
        :aria-expanded="showAttributeListDropdown"
        class="relative flex items-center w-full min-h-8 min-w-0"
        :class="{ 'cursor-pointer': !readOnly }"
        @click="openDropdown"
      >
        <span
          class="min-w-0 text-sm text-n-slate-12 truncate"
          :class="{ 'opacity-0': !attribute.value }"
        >
          {{ attribute.value || '\u00A0' }}
        </span>
      </button>
    </template>
  </MenuPopover>
</template>
