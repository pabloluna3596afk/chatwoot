<script setup>
import Input from 'dashboard/components-next/input/Input.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({ placeholder: { type: String, required: true } });
const search = defineModel({ type: String, default: '' });
</script>

<template>
  <div class="flex flex-wrap items-center justify-between gap-3 mb-4">
    <div class="flex flex-wrap items-center gap-2 min-w-0">
      <Input
        v-model="search"
        type="search"
        size="sm"
        :placeholder="placeholder"
        :aria-label="placeholder"
        class="w-56 [&>input]:!ps-8"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute top-1/2 -translate-y-1/2 start-2.5 size-3.5 text-n-slate-11"
          />
        </template>
      </Input>
      <slot name="filters" />
    </div>
    <div class="flex items-center gap-2"><slot name="actions" /></div>
  </div>
</template>
