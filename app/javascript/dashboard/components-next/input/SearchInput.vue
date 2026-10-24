<script setup>
import { ref } from 'vue';
import Input from './Input.vue';
defineProps({
  placeholder: { type: String, required: true },
  ariaLabel: { type: String, default: '' },
  size: {
    type: String,
    default: 'md',
    validator: value => ['sm', 'md'].includes(value),
  },
  clearable: { type: Boolean, default: false },
  disabled: { type: Boolean, default: false },
});

defineOptions({ inheritAttrs: false });

const modelValue = defineModel({ type: String, default: '' });
const container = ref(null);

const clearSearch = () => {
  modelValue.value = '';
  container.value.querySelector('input').focus();
};
</script>

<template>
  <div
    ref="container"
    :class="$attrs.class"
    :dir="$attrs.dir"
    class="relative w-full min-w-0 group"
  >
    <Input
      v-bind="{ ...$attrs, class: undefined }"
      v-model="modelValue"
      :placeholder="placeholder"
      :aria-label="ariaLabel || placeholder"
      :size="size"
      :disabled="disabled"
      type="search"
      class="[&>input]:min-h-11 md:[&>input]:min-h-0 [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8 [&>input]:!rounded-[0.625rem]"
      :class="{
        '[&>input]:ltr:!pr-11 [&>input]:rtl:!pl-11 md:[&>input]:ltr:!pr-8 md:[&>input]:rtl:!pl-8 [&>input::-webkit-search-cancel-button]:appearance-none':
          clearable,
      }"
    >
      <template #prefix>
        <span
          aria-hidden="true"
          class="i-lucide-search absolute top-1/2 -translate-y-1/2 pointer-events-none text-n-slate-11 group-focus-within:text-n-brand size-3.5 start-2.5"
        />
        <button
          v-if="clearable && modelValue"
          type="button"
          :disabled="disabled"
          :aria-label="$t('DATE_PICKER.CLEAR_BUTTON')"
          class="absolute end-0 top-1/2 -translate-y-1/2 flex items-center justify-center size-11 md:size-8 text-n-slate-11 hover:text-n-brand focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand rounded-lg disabled:opacity-50 disabled:cursor-not-allowed"
          @click="clearSearch"
        >
          <span aria-hidden="true" class="i-lucide-x size-4" />
        </button>
      </template>
    </Input>
  </div>
</template>
