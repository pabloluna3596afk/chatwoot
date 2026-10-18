<script setup>
import { computed, ref } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import WithLabel from './WithLabel.vue';

const props = defineProps({
  label: {
    type: String,
    required: true,
  },
  type: {
    type: String,
    default: 'text',
  },
  icon: {
    type: String,
    default: '',
  },
  name: {
    type: String,
    required: true,
  },
  hasError: Boolean,
  errorMessage: {
    type: String,
    default: '',
  },
  labelSrOnly: Boolean,
  outlined: Boolean,
  spacing: {
    type: String,
    default: 'base',
    validator: value => ['base', 'compact'].includes(value),
  },
});

const FIELDS = {
  TEXT: 'text',
  PASSWORD: 'password',
};

defineOptions({
  inheritAttrs: false,
});

const model = defineModel({
  type: [String, Number],
  required: true,
});

const isPasswordVisible = ref(false);

const isPasswordField = computed(() => props.type === FIELDS.PASSWORD);

const currentInputType = computed(() => {
  if (isPasswordField.value) {
    return isPasswordVisible.value ? FIELDS.TEXT : FIELDS.PASSWORD;
  }
  return props.type;
});
</script>

<template>
  <WithLabel
    :label="label"
    :icon="icon"
    :name="name"
    :has-error="hasError"
    :error-message="errorMessage"
    :label-sr-only="labelSrOnly"
  >
    <template #rightOfLabel>
      <slot />
    </template>
    <input
      v-bind="$attrs"
      :id="$attrs.id || name"
      v-model="model"
      :name="name"
      :type="currentInputType"
      :aria-label="label"
      class="block w-full appearance-none outline outline-1 focus:outline focus:outline-1 text-n-slate-12 placeholder:text-n-slate-10"
      :class="{
        'reset-base h-14 mb-0 rounded-xl border-0 bg-n-solid-1 px-4 py-3 text-base dark:bg-n-solid-3':
          outlined,
        'border-none rounded-md shadow-sm bg-n-alpha-black2 sm:text-sm sm:leading-6':
          !outlined,
        'error outline-n-ruby-8 dark:outline-n-ruby-8 hover:outline-n-ruby-9 dark:hover:outline-n-ruby-9 disabled:outline-n-ruby-8 dark:disabled:outline-n-ruby-8':
          hasError,
        'outline-n-weak hover:outline-n-slate-6 focus:outline-n-brand dark:focus:outline-n-brand':
          !hasError,
        'dark:outline-n-slate-7 dark:hover:outline-n-slate-8':
          outlined && !hasError,
        'dark:outline-n-weak dark:hover:outline-n-slate-6':
          !outlined && !hasError,
        'px-3 py-3': !outlined && spacing === 'base',
        'px-3 py-2 mb-0': !outlined && spacing === 'compact',
        'ps-9': icon,
        'pe-12': outlined && isPasswordField,
        'pe-10': !outlined && isPasswordField,
      }"
    />
    <Button
      v-if="isPasswordField"
      type="button"
      slate
      sm
      link
      :icon="isPasswordVisible ? 'i-lucide-eye-off' : 'i-lucide-eye'"
      class="absolute inset-y-0 end-0"
      :class="outlined ? '!h-full !px-3' : 'pe-3'"
      :aria-label="
        isPasswordVisible
          ? $t('LOGIN.PASSWORD.HIDE')
          : $t('LOGIN.PASSWORD.SHOW')
      "
      :aria-pressed="isPasswordVisible"
      @click="isPasswordVisible = !isPasswordVisible"
    />
  </WithLabel>
</template>
