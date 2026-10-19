<script setup>
import { onMounted, ref } from 'vue';
import { AUTH_LINK_CLASS } from './authStyles';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  stepName: { type: String, required: true },
  current: { type: Number, required: true },
  total: { type: Number, default: 5 },
  backTo: { type: Object, default: null },
  backDisabled: Boolean,
});
const heading = ref(null);
onMounted(() => heading.value.focus({ preventScroll: true }));
</script>

<template>
  <header class="mb-6 space-y-6">
    <div class="space-y-3">
      <RouterLink
        v-if="backTo"
        :to="backTo"
        :class="AUTH_LINK_CLASS"
        :aria-disabled="backDisabled"
        :tabindex="backDisabled ? -1 : undefined"
        data-testid="onboarding-back"
        @click.capture="backDisabled && $event.preventDefault()"
      >
        <span
          class="i-lucide-arrow-left size-4 rtl:rotate-180"
          aria-hidden="true"
        />
        {{ $t('ONBOARDING_AUTH.BACK') }}
      </RouterLink>
      <p
        class="m-0 text-sm font-medium leading-6 text-n-slate-11"
        aria-live="polite"
      >
        {{ $t('ONBOARDING_AUTH.STEP', { current, total, name: stepName }) }}
      </p>
      <div
        role="progressbar"
        :aria-label="$t('ONBOARDING_AUTH.PROGRESS')"
        :aria-valuenow="current"
        :aria-valuemin="0"
        :aria-valuemax="total"
        :aria-valuetext="
          $t('ONBOARDING_AUTH.STEP', { current, total, name: stepName })
        "
        class="flex gap-2 py-1"
      >
        <span
          v-for="step in total"
          :key="step"
          class="h-2 flex-1 rounded-full motion-safe:transition-colors motion-safe:duration-200"
          :class="[
            step <= current ? 'bg-n-brand' : 'bg-n-slate-5',
            step === current &&
              'ring-2 ring-n-brand/30 ring-offset-2 ring-offset-n-solid-1 dark:ring-offset-n-background',
          ]"
          :data-step-state="
            step < current
              ? 'completed'
              : step === current
                ? 'current'
                : 'upcoming'
          "
          aria-hidden="true"
        />
      </div>
    </div>
    <slot name="brand" />
    <div class="space-y-3">
      <h1
        ref="heading"
        tabindex="-1"
        class="m-0 text-balance text-3xl font-semibold leading-tight tracking-tight text-n-slate-12 outline-none sm:text-4xl"
      >
        {{ title }}
      </h1>
      <p
        v-if="subtitle || $slots.default"
        class="m-0 break-words text-base leading-6 text-n-slate-11 [overflow-wrap:anywhere]"
      >
        <slot>{{ subtitle }}</slot>
      </p>
    </div>
  </header>
</template>
