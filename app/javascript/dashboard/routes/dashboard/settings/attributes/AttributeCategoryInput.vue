<script setup>
import { computed, ref } from 'vue';
import Input from 'dashboard/components/widgets/forms/Input.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const props = defineProps({
  options: { type: Array, default: () => [] },
  label: { type: String, default: '' },
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
      <Input
        v-model="value"
        class="w-full"
        :label="label"
        :placeholder="placeholder"
        @click="showSuggestions()"
        @input="showSuggestions"
      />
    </template>
  </MenuPopover>
</template>
