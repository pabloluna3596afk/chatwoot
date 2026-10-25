<script setup>
import {
  computed,
  ref,
  onMounted,
  nextTick,
  getCurrentInstance,
  useAttrs,
} from 'vue';
const props = defineProps({
  modelValue: { type: [String, Number], default: '' },
  type: { type: String, default: 'text' },
  customInputClass: { type: [String, Object, Array], default: '' },
  placeholder: { type: String, default: '' },
  label: { type: String, default: '' },
  id: { type: String, default: '' },
  size: {
    type: String,
    default: 'md',
    validator: value => ['sm', 'md'].includes(value),
  },
  help: { type: String, default: '' },
  message: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
  messageType: {
    type: String,
    default: 'info',
    validator: value => ['info', 'error', 'success'].includes(value),
  },
  min: { type: String, default: '' },
  max: { type: String, default: '' },
  autofocus: { type: Boolean, default: false },
});

const emit = defineEmits([
  'update:modelValue',
  'blur',
  'input',
  'focus',
  'enter',
]);

defineOptions({ inheritAttrs: false });

// Generate a unique ID per component instance when `id` prop is not provided.
const { uid } = getCurrentInstance();
const uniqueId = computed(() => props.id || `input-${uid}`);
const attrs = useAttrs();
// Keep caller layout and container selectors; accessible attributes belong to the input.
const containerAttrs = () =>
  Object.fromEntries(
    Object.entries(attrs).filter(
      ([name]) => ['class', 'style'].includes(name) || name.startsWith('data-')
    )
  );

const isFocused = ref(false);
const inputRef = ref(null);

const messageClass = computed(() => {
  switch (props.messageType) {
    case 'error':
      return 'text-n-ruby-9 dark:text-n-ruby-9';
    case 'success':
      return 'text-n-teal-10 dark:text-n-teal-10';
    default:
      return 'text-n-slate-11 dark:text-n-slate-11';
  }
});

const inputOutlineClass = computed(() => {
  switch (props.messageType) {
    case 'error':
      return 'outline-n-ruby-8 dark:outline-n-ruby-8 hover:outline-n-ruby-9 dark:hover:outline-n-ruby-9 disabled:outline-n-ruby-8 dark:disabled:outline-n-ruby-8';
    default:
      return 'outline-n-weak dark:outline-n-weak hover:outline-n-slate-6 dark:hover:outline-n-slate-6 disabled:outline-n-weak dark:disabled:outline-n-weak focus:outline-n-brand dark:focus:outline-n-brand';
  }
});

const handleInput = event => {
  let value = event.target.value;
  // Convert to number if type is number and value is not empty
  if (props.type === 'number' && value !== '') {
    value = Number(value);
  }
  emit('update:modelValue', value);
  emit('input', event);
};

const handleFocus = event => {
  emit('focus', event);
  isFocused.value = true;
};

const sizeClass = computed(() => {
  switch (props.size) {
    case 'sm':
      return 'h-8 !px-3 !py-2';
    case 'md':
      return 'h-10 !px-3 !py-2.5';
    default:
      return 'h-10 !px-3 !py-2.5';
  }
});

const handleBlur = event => {
  emit('blur', event);
  isFocused.value = false;
};

const handleEnter = event => {
  emit('enter', event);
};

onMounted(() => {
  if (props.autofocus) {
    nextTick(() => {
      inputRef.value?.focus();
    });
  }
});
</script>

<template>
  <div v-bind="containerAttrs()" class="relative flex flex-col min-w-0 gap-1">
    <label
      v-if="label"
      :for="uniqueId"
      class="mb-0.5 text-heading-3 text-n-slate-12"
    >
      {{ label }}
    </label>
    <!-- Added prefix slot to allow adding icons to the input -->
    <slot name="prefix" />
    <input
      :id="uniqueId"
      v-bind="$attrs"
      ref="inputRef"
      :aria-invalid="messageType === 'error' ? true : $attrs['aria-invalid']"
      :aria-describedby="
        [
          $attrs['aria-describedby'],
          help ? `${uniqueId}-help` : '',
          message ? `${uniqueId}-message` : '',
        ]
          .filter(Boolean)
          .join(' ') || undefined
      "
      :value="modelValue"
      :class="[
        customInputClass,
        inputOutlineClass,
        sizeClass,
        {
          error: messageType === 'error',
          focus: isFocused,
        },
      ]"
      :type="type"
      :placeholder="placeholder"
      :disabled="disabled"
      :min="['date', 'datetime-local', 'time'].includes(type) ? min : undefined"
      :max="
        ['date', 'datetime-local', 'time', 'number'].includes(type)
          ? max
          : undefined
      "
      class="max-sm:!min-h-11 block w-full reset-base text-sm !mb-0 outline outline-1 border-none border-0 outline-offset-[-1px] rounded-lg bg-n-alpha-black2 file:border-0 file:bg-transparent file:text-sm file:font-medium text-ellipsis placeholder:text-n-slate-10 dark:placeholder:text-n-slate-10 disabled:cursor-not-allowed disabled:opacity-50 text-n-slate-12 transition-all duration-500 ease-in-out [appearance:textfield] [&::-webkit-inner-spin-button]:appearance-none [&::-webkit-outer-spin-button]:appearance-none"
      @input="handleInput"
      @focus="handleFocus"
      @blur="handleBlur"
      @keyup.enter="handleEnter"
    />
    <p
      v-if="help"
      :id="`${uniqueId}-help`"
      class="mb-0 text-label-small text-n-slate-11 whitespace-pre-line break-words"
    >
      {{ help }}
    </p>
    <p
      v-if="message"
      :id="`${uniqueId}-message`"
      :role="messageType === 'error' ? 'alert' : undefined"
      class="min-w-0 mt-1 mb-0 text-label-small whitespace-pre-line break-words transition-all duration-500 ease-in-out"
      :class="messageClass"
    >
      {{ message }}
    </p>
  </div>
</template>
