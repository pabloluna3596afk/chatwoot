<script setup>
defineProps({
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
});
</script>

<template>
  <header class="flex w-full flex-col items-start">
    <div
      v-if="title || $slots.title || $slots.actions"
      class="mb-2 flex min-h-8 w-full items-center justify-between gap-4"
    >
      <slot name="title">
        <h1 class="min-w-0 break-words text-heading-1 text-n-slate-12">
          {{ title }}
        </h1>
      </slot>
      <div v-if="$slots.actions" class="flex shrink-0 items-center gap-3">
        <slot name="actions" />
      </div>
    </div>
    <div
      v-if="
        description || $slots.description || $slots.context || $slots.moreInfo
      "
      class="flex w-full flex-col gap-1.5 text-n-slate-11"
    >
      <p
        v-if="description || $slots.description || $slots.context"
        class="mb-0 line-clamp-5 max-w-3xl text-body-main sm:line-clamp-none"
      >
        <slot name="description">{{ description }}</slot>
        <slot name="context" />
      </p>
      <slot name="moreInfo" />
    </div>
    <div
      v-if="$slots.toolbar"
      class="flex min-w-0 w-full flex-wrap items-center justify-between gap-3 sm:mt-8"
    >
      <slot name="toolbar" />
    </div>
  </header>
</template>
