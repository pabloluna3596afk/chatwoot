<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({ task: { type: Object, required: true } });
defineEmits(['dismiss']);
const router = useRouter();
const openTask = () => {
  if (props.task.link) router.push(props.task.link.route);
};
const accent = computed(
  () =>
    ({
      running: 'border-s-n-brand bg-n-solid-1 text-n-slate-12',
      success: 'border-s-n-teal-9 bg-n-teal-2 text-n-teal-11',
      error: 'border-s-n-ruby-9 bg-n-ruby-2 text-n-ruby-11',
    })[props.task.status]
);
</script>

<template>
  <article
    :role="task.link ? 'link' : 'status'"
    :tabindex="task.link ? 0 : undefined"
    :aria-label="task.link?.label"
    aria-live="polite"
    aria-atomic="true"
    class="pointer-events-auto flex min-h-11 shrink-0 animate-fade-in-up items-center gap-2 rounded-lg border border-n-weak border-s-4 px-3 py-2 shadow-md motion-reduce:animate-none"
    :class="[
      accent,
      {
        'cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-n-brand':
          task.link,
      },
    ]"
    @click="openTask"
    @keydown.enter.self.prevent="openTask"
  >
    <span
      v-if="task.status === 'running'"
      class="relative size-4 shrink-0"
      aria-hidden="true"
    >
      <svg
        viewBox="0 0 24 24"
        class="absolute inset-0 size-4 fill-none stroke-n-blue-5 stroke-2"
      >
        <circle cx="12" cy="12" r="9" />
      </svg>
      <Spinner
        :size="16"
        class="absolute inset-0 stroke-2 text-n-brand motion-reduce:animate-none"
      />
    </span>
    <Icon
      v-else
      :icon="
        task.status === 'success' ? 'i-lucide-check' : 'i-lucide-circle-alert'
      "
      class="size-4 shrink-0"
      aria-hidden="true"
    />
    <div class="min-w-0 flex-1">
      <p
        :title="task.title"
        class="m-0 truncate text-sm font-medium leading-4 text-n-slate-12"
      >
        {{ task.title }}
      </p>
      <p
        v-if="task.detail"
        :title="task.detail"
        class="m-0 truncate text-xs leading-4 text-n-slate-11"
      >
        {{ task.detail }}
      </p>
    </div>
    <Button
      v-if="task.status !== 'running'"
      intent="tertiary"
      size="xs"
      class="!size-5 shrink-0"
      icon="i-lucide-x"
      :aria-label="$t('BACKGROUND_TASKS.CLOSE')"
      @click.stop="$emit('dismiss', task.id)"
    />
  </article>
</template>
