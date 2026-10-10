<script setup>
import { computed, ref } from 'vue';
import Input from 'dashboard/components/widgets/forms/Input.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  options: { type: Array, default: () => [] },
  label: { type: String, default: '' },
  // Shown as an info icon next to the label instead of a paragraph under the field.
  help: { type: String, default: '' },
  placeholder: { type: String, default: '' },
});
const value = defineModel({ type: String, default: '' });
const open = ref(false);
const items = computed(() =>
  props.options
    .filter(option =>
      option.toLocaleLowerCase().includes(value.value.toLocaleLowerCase())
    )
    .map(option => ({
      label: option,
      value: option,
      isSelected: option === value.value,
    }))
);
const showSuggestions = (query = value.value) => {
  open.value = props.options.some(option =>
    option.toLocaleLowerCase().includes(query.toLocaleLowerCase())
  );
};
</script>

<template>
  <MenuPopover
    v-model:open="open"
    :menu-items="items"
    :label="label"
    match-width
    align="start"
    @action="value = $event.value"
  >
    <template #trigger>
      <div class="w-full">
        <span
          v-if="label"
          class="flex items-center gap-1.5 mb-1 text-heading-3"
        >
          {{ label }}
          <span
            v-if="help"
            v-tooltip.top="help"
            class="i-lucide-info size-3.5 text-n-slate-10"
            role="img"
            :aria-label="help"
            data-testid="category-help"
          />
        </span>
        <Input
          v-model="value"
          class="w-full"
          :aria-label="label"
          :placeholder="placeholder"
          @click="showSuggestions()"
          @input="showSuggestions"
        />
      </div>
    </template>
  </MenuPopover>
</template>
