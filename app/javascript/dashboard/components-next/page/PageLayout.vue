<script setup>
import PageHeader from './PageHeader.vue';

defineProps({
  title: {
    type: String,
    default: '',
  },
  description: {
    type: String,
    default: '',
  },
  width: {
    type: String,
    default: 'settings',
    validator: value => ['settings', 'wide', 'full'].includes(value),
  },
});
</script>

<template>
  <section class="flex h-full min-h-0 w-full flex-col gap-4 overflow-hidden">
    <div
      class="mx-auto w-full shrink-0"
      :class="{
        'max-w-5xl': width === 'settings',
        'max-w-[90rem]': width === 'wide',
        'max-w-none': width === 'full',
      }"
    >
      <PageHeader :title="title" :description="description">
        <template v-if="$slots.title" #title><slot name="title" /></template>
        <template v-if="$slots.description" #description>
          <slot name="description" />
        </template>
        <template v-if="$slots.context" #context>
          <slot name="context" />
        </template>
        <template v-if="$slots.moreInfo" #moreInfo>
          <slot name="moreInfo" />
        </template>
        <template v-if="$slots.actions" #actions>
          <slot name="actions" />
        </template>
        <template v-if="$slots.toolbar" #toolbar>
          <slot name="toolbar" />
        </template>
      </PageHeader>
    </div>
    <main class="min-h-0 flex-1 overflow-y-auto">
      <div
        class="mx-auto flex min-h-full w-full flex-col"
        :class="{
          'max-w-5xl': width === 'settings',
          'max-w-[90rem]': width === 'wide',
          'max-w-none': width === 'full',
        }"
      >
        <slot name="banner" />
        <slot />
      </div>
    </main>
    <footer v-if="$slots.footer" class="mx-auto w-full shrink-0">
      <div
        class="mx-auto w-full"
        :class="{
          'max-w-5xl': width === 'settings',
          'max-w-[90rem]': width === 'wide',
          'max-w-none': width === 'full',
        }"
      >
        <slot name="footer" />
      </div>
    </footer>
  </section>
</template>
