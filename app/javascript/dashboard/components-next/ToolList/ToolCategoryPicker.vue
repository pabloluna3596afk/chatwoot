<script setup>
import { computed, ref } from 'vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';

const props = defineProps({
  modelValue: { type: String, default: '' },
  categories: { type: Array, default: () => [] },
  label: { type: String, default: '' },
  placeholder: { type: String, default: '' },
  createLabel: { type: String, default: 'Create' },
  clearLabel: { type: String, default: 'Clear category' },
});
const emit = defineEmits(['update:modelValue', 'create']);
const query = ref('');
const normalize = value =>
  value
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .trim()
    .replace(/\s+/g, ' ')
    .toLocaleLowerCase();
const matchingCategories = computed(() =>
  props.categories.filter(name =>
    normalize(name).includes(normalize(query.value))
  )
);
const options = computed(() =>
  matchingCategories.value.map(name => ({ value: name, label: name }))
);
const hasExactMatch = computed(() =>
  props.categories.some(name => normalize(name) === normalize(query.value))
);
const createCategory = () => {
  const cleaned = query.value.trim().replace(/\s+/g, ' ');
  if (
    !cleaned ||
    props.categories.some(name => normalize(name) === normalize(cleaned))
  )
    return;
  emit('create', cleaned);
  emit('update:modelValue', cleaned);
};
const onSearch = value => {
  query.value = value;
  const match = props.categories.find(
    name => normalize(name) === normalize(value)
  );
  if (match) emit('update:modelValue', match);
};
</script>

<template>
  <div class="flex min-w-0 flex-col gap-2">
    <ComboBox
      :model-value="modelValue"
      :options="options"
      :label="label"
      :placeholder="placeholder"
      :search-placeholder="placeholder"
      :show-search="true"
      :use-api-results="true"
      :allow-deselect="true"
      @update:model-value="emit('update:modelValue', $event)"
      @search="onSearch"
    >
      <template #footer="{ close }"
        ><div class="border-t border-n-weak p-2">
          <button
            type="button"
            class="w-full rounded-md px-3 py-2 text-start text-sm text-n-brand hover:bg-n-alpha-2"
            :disabled="!query.trim() || hasExactMatch"
            @click="
              createCategory();
              close();
            "
          >
            {{ createLabel }} «{{ query.trim() }}»
          </button>
        </div></template
      >
    </ComboBox>
    <button
      v-if="modelValue"
      type="button"
      class="self-start text-xs text-n-slate-10 underline"
      @click="emit('update:modelValue', '')"
    >
      {{ clearLabel }}
    </button>
  </div>
</template>
