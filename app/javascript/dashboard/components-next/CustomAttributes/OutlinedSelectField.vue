<script setup>
/**
 * Outlined floating-label select using DropdownMenu (same pattern as list custom attributes).
 */
import { computed, ref } from 'vue';
import OutlinedAttributeField from 'dashboard/components-next/CustomAttributes/OutlinedAttributeField.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import Avatar from 'next/avatar/Avatar.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  label: { type: String, required: true },
  options: { type: Array, default: () => [] },
  selectedItem: { type: Object, default: null },
  placeholder: { type: String, default: '' },
  showSearch: { type: Boolean, default: true },
  disabled: { type: Boolean, default: false },
  /** Show avatar thumbnails in the menu (agents). */
  hasThumbnail: { type: Boolean, default: false },
});

const emit = defineEmits(['select']);

const showMenu = ref(false);

const hasValue = computed(() => {
  const item = props.selectedItem;
  if (!item) return false;
  // id 0 / null used as "None"
  return item.id !== null && item.id !== undefined && item.id !== 0;
});

const displayLabel = computed(() => {
  if (hasValue.value) return props.selectedItem.name || '';
  return props.selectedItem?.name || props.placeholder || '';
});

const sameId = (a, b) => {
  if (a === b) return true;
  if (a == null || b == null) return a === b;
  return String(a) === String(b);
};

// A person and an assistant can share the same numeric id, so when both carry an assignee type
// (people, bots, Captain) the type has to match too or two rows would show as selected.
const isSelectedOption = option => {
  const selected = props.selectedItem;
  if (!selected || !sameId(option.id, selected.id)) return false;
  if (!option.assignee_type || !selected.assignee_type) return true;
  return option.assignee_type === selected.assignee_type;
};

const menuItems = computed(() =>
  (props.options || []).map(option => ({
    label: option.name,
    value: option.id,
    action: 'select',
    isSelected: isSelectedOption(option),
    // The image already identifies the assignee; the icon is only the fallback when there is none.
    icon: option.thumbnail ? undefined : option.icon || undefined,
    thumbnail:
      props.hasThumbnail && option.name
        ? {
            name: option.name,
            src: option.thumbnail || '',
          }
        : undefined,
    option,
  }))
);

const onTriggerClick = () => {
  if (!props.disabled) showMenu.value = !showMenu.value;
};

const onAction = item => {
  const selected =
    item.option || props.options.find(o => sameId(o.id, item.value)) || null;
  emit('select', selected);
};
</script>

<template>
  <OutlinedAttributeField
    :label="label"
    filled
    :focused="showMenu"
    :disabled="disabled"
  >
    <MenuPopover
      v-model:open="showMenu"
      :menu-items="menuItems"
      :show-search="showSearch"
      :label="label"
      match-width
      align="start"
      panel-class="min-w-[14rem] max-w-[calc(100vw-2rem)]"
      @action="onAction"
    >
      <template #trigger>
        <button
          type="button"
          :disabled="disabled"
          :aria-label="label"
          aria-haspopup="menu"
          :aria-expanded="showMenu"
          class="relative flex items-center justify-start w-full min-h-8 gap-1.5 text-start"
          :class="{ 'cursor-pointer': !disabled, 'z-50': showMenu }"
          @click="onTriggerClick"
        >
          <Avatar
            v-if="hasThumbnail && hasValue"
            :name="selectedItem.name"
            :src="selectedItem.thumbnail"
            :status="selectedItem.availability_status"
            :size="20"
            hide-offline-status
            rounded-full
            class="shrink-0"
          />
          <Icon
            v-else-if="hasValue && selectedItem.icon"
            :icon="selectedItem.icon"
            class="size-4 shrink-0 text-n-slate-11"
          />
          <span
            class="flex-1 min-w-0 text-sm text-start truncate"
            :class="hasValue ? 'text-n-slate-12' : 'text-n-slate-11'"
          >
            {{ displayLabel || '\u00A0' }}
          </span>
          <span
            class="i-lucide-chevron-down size-3.5 shrink-0 text-n-slate-11"
            :class="{ 'rotate-180': showMenu }"
          />
        </button>
      </template>
    </MenuPopover>
  </OutlinedAttributeField>
</template>
