<script setup>
import { computed, useId } from 'vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

const props = defineProps({
  icon: { type: [String, Number], default: 'plain' },
  title: { type: String, required: true },
  value: { type: String, default: '' },
  expanded: Boolean,
  disabled: Boolean,
});
const contentId = useId();
const isDone = computed(() => props.icon === 'done');
const isPlain = computed(() => props.icon === 'plain');
</script>

<template>
  <section class="min-w-0 py-3" :class="{ 'opacity-60': disabled }">
    <div
      class="grid min-w-0 grid-cols-[1.375rem_minmax(0,11rem)_minmax(0,1fr)_auto] items-center gap-x-3 max-md:grid-cols-[1.375rem_minmax(0,1fr)]"
    >
      <span
        v-if="!isPlain"
        class="flex size-[1.375rem] items-center justify-center rounded-full"
        :class="isDone ? 'bg-n-teal-9 text-white' : 'border border-n-strong'"
        aria-hidden="true"
      >
        <Icon v-if="isDone" icon="i-lucide-check" class="size-3.5" />
      </span>
      <Icon
        v-else
        icon="i-lucide-list"
        class="size-5 text-n-slate-11"
        aria-hidden="true"
      />
      <h2 class="m-0 text-body-main font-medium text-n-slate-12">
        {{ title }}
      </h2>
      <p
        v-if="value"
        class="m-0 min-w-0 text-body-main text-n-slate-11 max-md:col-start-2 max-md:mt-1"
      >
        {{ value }}
      </p>
      <div class="flex items-center gap-2 max-md:col-start-2 max-md:mt-2">
        <slot name="actions" :content-id="contentId" :expanded="expanded" />
      </div>
    </div>
    <div
      v-show="expanded"
      :id="contentId"
      class="ms-[2.125rem] mt-3 flex min-w-0 flex-col gap-3"
      :aria-expanded="expanded"
    >
      <slot />
    </div>
  </section>
</template>
