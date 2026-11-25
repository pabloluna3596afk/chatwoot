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
      running: 'border-n-brand bg-n-solid-1 text-n-slate-12',
      success: 'border-n-teal-9 bg-n-teal-2 text-n-teal-11',
      error: 'border-n-ruby-9 bg-n-ruby-2 text-n-ruby-11',
    })[props.task.status]
);
</script>

<template>
  <article
    role="status"
    aria-live="polite"
    aria-atomic="true"
    class="pointer-events-auto flex shrink-0 animate-fade-in-up gap-3 rounded-xl border border-s-4 p-3 shadow-lg motion-reduce:animate-none"
    :class="accent"
  >
    <Spinner
      v-if="task.status === 'running'"
      :size="20"
      class="mt-0.5 shrink-0 motion-reduce:animate-none"
      aria-hidden="true"
    />
    <Icon
      v-else
      :icon="
        task.status === 'success' ? 'i-lucide-check' : 'i-lucide-circle-alert'
      "
      class="mt-0.5 size-5 shrink-0"
      aria-hidden="true"
    />
    <div class="min-w-0 flex-1">
      <p class="m-0 break-words text-sm font-medium text-n-slate-12">
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
