<script setup>
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';

defineProps({
  id: { type: [String, Number], required: true },
  title: { type: String, required: true },
  description: { type: String, default: '' },
  icon: { type: [String, Object, Function], default: null },
  tags: { type: Array, default: () => [] },
  actionLabel: { type: String, default: '' },
  actionIcon: { type: String, default: '' },
  disabled: { type: Boolean, default: false },
});

const emit = defineEmits(['apply']);

const tagClasses = color => {
  const colors = {
    teal: 'bg-n-teal-3 text-n-teal-11',
    amber: 'bg-n-amber-3 text-n-amber-11',
    blue: 'bg-n-blue-3 text-n-blue-11',
    slate: 'bg-n-slate-3 text-n-slate-11',
  };
  return colors[color] || colors.slate;
};
</script>

<template>
  <article
    class="flex flex-col gap-2 rounded-xl border border-n-weak p-4"
    :class="{ 'opacity-60': disabled }"
    :data-testid="`preset-${id}`"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="flex min-w-0 items-start gap-2">
        <Icon
          v-if="icon"
          :icon="icon"
          class="mt-0.5 shrink-0 text-n-slate-11"
        />
        <h3 class="text-heading-3 text-n-slate-12">{{ title }}</h3>
      </div>
      <div v-if="tags.length" class="flex shrink-0 flex-wrap justify-end gap-1">
        <span
          v-for="(tag, index) in tags"
          :key="`${tag.label}-${index}`"
          class="inline-flex rounded-md px-2 py-0.5 text-xs font-medium"
          :class="tagClasses(tag.color)"
        >
          {{ tag.label }}
        </span>
      </div>
    </div>
    <p v-if="description" class="text-body-main text-n-slate-11">
      {{ description }}
    </p>
    <div v-if="$slots.preview" class="text-n-slate-12">
      <slot name="preview" />
    </div>
    <div v-if="$slots.meta" class="text-xs text-n-slate-10">
      <slot name="meta" />
    </div>
    <div v-if="$slots.actions || actionLabel" class="mt-auto">
      <slot name="actions">
        <Button
          :label="actionLabel"
          :icon="actionIcon"
          size="sm"
          intent="primary"
          :disabled="disabled"
          :aria-label="`${actionLabel}: ${title}`"
          @click="emit('apply', id)"
        />
      </slot>
    </div>
  </article>
</template>
