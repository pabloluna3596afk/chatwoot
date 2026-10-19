<script setup>
import { computed, ref } from 'vue';
import AuthFeedback from './AuthFeedback.vue';
import {
  AUTH_FIELD_CLASS,
  AUTH_LABEL_CLASS,
  AUTH_LINK_CLASS,
} from './authStyles';

const props = defineProps({
  id: { type: String, required: true },
  label: { type: String, required: true },
  type: { type: String, default: 'text' },
  error: { type: String, default: '' },
  describedby: { type: String, default: '' },
});
defineOptions({ inheritAttrs: false });
const model = defineModel({ type: String, required: true });
const visible = ref(false);
const inputType = computed(() =>
  props.type === 'password' && visible.value ? 'text' : props.type
);
const description = computed(
  () =>
    [props.describedby, props.error && `${props.id}-error`]
      .filter(Boolean)
      .join(' ') || undefined
);
</script>

<template>
  <div class="space-y-2">
    <label :for="id" :class="AUTH_LABEL_CLASS">{{ label }}</label>
    <div class="relative">
      <input
        v-bind="$attrs"
        :id="id"
        v-model="model"
        :type="inputType"
        :aria-label="label"
        :class="[
          AUTH_FIELD_CLASS,
          { 'pe-14': type === 'password', '!border-n-ruby-11': error },
        ]"
        :aria-invalid="Boolean(error)"
        :aria-describedby="description"
      />
      <button
        v-if="type === 'password'"
        type="button"
        :class="AUTH_LINK_CLASS"
        class="absolute inset-y-0 end-0 w-12"
        :aria-label="
          visible ? $t('LOGIN.PASSWORD.HIDE') : $t('LOGIN.PASSWORD.SHOW')
        "
        :aria-pressed="visible"
        @click="visible = !visible"
      >
        <span
          :class="visible ? 'i-lucide-eye-off' : 'i-lucide-eye'"
          class="size-5"
          aria-hidden="true"
        />
      </button>
    </div>
    <AuthFeedback v-if="error" :id="`${id}-error`" error>
      {{ error }}
    </AuthFeedback>
  </div>
</template>
