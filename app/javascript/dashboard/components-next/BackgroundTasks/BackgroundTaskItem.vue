<script setup>
import { computed } from 'vue';
import { useRouter } from 'vue-router';
import Button from 'dashboard/components-next/button/Button.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Spinner from 'dashboard/components-next/spinner/Spinner.vue';

const props = defineProps({ task: { type: Object, required: true } });
defineEmits(['dismiss']);
const router = useRouter();
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
    role="status"
    aria-live="polite"
    aria-atomic="true"
    class="pointer-events-auto flex shrink-0 animate-fade-in-up gap-3 rounded-xl border border-n-weak border-s-4 p-3 shadow-lg motion-reduce:animate-none"
    :class="accent"
  >
    <span
      v-if="task.status === 'running'"
      class="relative mt-0.5 size-5 shrink-0"
      aria-hidden="true"
    >
      <svg
        viewBox="0 0 24 24"
        class="absolute inset-0 size-5 fill-none stroke-n-blue-5 stroke-2"
      >
        <circle cx="12" cy="12" r="9" />
      </svg>
      <Spinner
        :size="20"
        class="absolute inset-0 stroke-2 text-n-brand motion-reduce:animate-none"
      />
    </span>
    <Icon
      v-else
      :icon="
        task.status === 'success' ? 'i-lucide-check' : 'i-lucide-circle-alert'
      "
      class="mt-0.5 size-5 shrink-0"
      aria-hidden="true"
    />
    <div class="min-w-0 flex-1">
      <p
        :title="task.title"
        class="m-0 truncate text-sm font-medium text-n-slate-12"
      >
        {{ task.title }}
      </p>
      <p
        v-if="task.detail"
        class="m-0 mt-1 break-words text-xs text-n-slate-11"
      >
        {{ task.detail }}
      </p>
      <Button
        v-if="task.link"
        intent="link"
        size="sm"
        :label="task.link.label"
        @click="router.push(task.link.route)"
      />
    </div>
    <Button
      v-if="task.status !== 'running'"
      intent="tertiary"
      size="sm"
      icon="i-lucide-x"
      :aria-label="$t('BACKGROUND_TASKS.CLOSE')"
      @click="$emit('dismiss', task.id)"
    />
  </article>
</template>
