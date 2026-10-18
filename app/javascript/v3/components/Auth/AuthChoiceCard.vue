<script setup>
defineProps({
  name: { type: String, required: true },
  value: { type: String, required: true },
  label: { type: String, required: true },
  description: { type: String, required: true },
  icon: { type: String, required: true },
  first: Boolean,
  disabled: Boolean,
  invalid: Boolean,
  required: Boolean,
});
const model = defineModel({ type: String, required: true });
const ARROW_STEPS = { ArrowRight: 1, ArrowDown: 1, ArrowLeft: -1, ArrowUp: -1 };
const onKeydown = event => {
  const step = ARROW_STEPS[event.key];
  if (!step) return;
  event.preventDefault();
  const radios = [
    ...event.currentTarget
      .closest('[role="radiogroup"]')
      .querySelectorAll('input[type="radio"]'),
  ];
  const next =
    radios[
      (radios.indexOf(event.currentTarget) + step + radios.length) %
        radios.length
    ];
  next.click();
  next.focus();
};
</script>

<template>
  <label class="relative min-w-0 cursor-pointer">
    <input
      v-model="model"
      type="radio"
      role="radio"
      :name="name"
      :value="value"
      :disabled="disabled"
      :required="required"
      :aria-invalid="invalid"
      :tabindex="model === value || (!model && first) ? 0 : -1"
      class="peer sr-only"
      @keydown="onKeydown"
    />
    <span
      class="flex h-full min-h-20 flex-col gap-2 rounded-xl border border-n-slate-9 dark:border-n-slate-10 p-3 text-start text-n-slate-12 hover:border-n-slate-11 hover:bg-n-slate-2 peer-checked:border-n-brand dark:peer-checked:border-n-brand peer-checked:bg-n-blue-2 peer-focus-visible:outline peer-focus-visible:outline-2 peer-focus-visible:outline-offset-2 peer-focus-visible:outline-n-brand peer-disabled:cursor-not-allowed peer-disabled:opacity-60 motion-safe:transition-colors motion-safe:duration-150"
    >
      <span :class="icon" class="size-5 shrink-0" aria-hidden="true" />
      <span class="min-w-0 space-y-1">
        <span class="block break-words text-sm font-medium leading-5">{{
          label
        }}</span>
        <span class="block break-words text-sm leading-5 text-n-slate-11">{{
          description
        }}</span>
      </span>
    </span>
    <span
      class="i-lucide-circle-check absolute end-3 top-3 hidden size-4 text-n-brand peer-checked:block"
      aria-hidden="true"
    />
  </label>
</template>
