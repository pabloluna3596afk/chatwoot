<script setup>
/* Catalog fields and repeated copy use translation keys derived at runtime. */
/* eslint-disable @intlify/vue-i18n/no-dynamic-keys */
import { ref, onMounted, onBeforeUnmount, nextTick } from 'vue';
import { useScrollLock } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import Button from 'next/button/Button.vue';
import PlanCatalog from './PlanCatalog.vue';
import { planViewProps } from './planPresentation';

const props = defineProps(planViewProps);
const emit = defineEmits(['select', 'requestUpgrade', 'continue', 'close']);
const { t } = useI18n();
const config = useMapGetter('globalConfig/get');
const overlay = ref(null);
const scrollLocked = useScrollLock(document.body);
const previousFocus = document.activeElement;
const previousLock = scrollLocked.value;
let background = [];
const close = () => emit('close');
const onKeydown = event => {
  if (event.key === 'Escape') {
    event.preventDefault();
    close();
  }
  if (event.key !== 'Tab') return;
  const controls = [
    ...overlay.value.querySelectorAll(
      'button:not(:disabled), a[href], [tabindex="0"]'
    ),
  ];
  const first = controls[0];
  const last = controls[controls.length - 1];
  if (event.shiftKey && document.activeElement === first) {
    event.preventDefault();
    last.focus();
  } else if (!event.shiftKey && document.activeElement === last) {
    event.preventDefault();
    first.focus();
  }
};
onMounted(() =>
  nextTick(() => {
    background = [...document.body.children]
      .filter(element => element !== overlay.value)
      .map(element => ({ element, inert: element.inert }));
    background.forEach(({ element }) => {
      element.inert = true;
    });
    scrollLocked.value = true;
    overlay.value.querySelector('button').focus();
  })
);
onBeforeUnmount(() => {
  background.forEach(({ element, inert }) => {
    element.inert = inert;
  });
  scrollLocked.value = previousLock;
  previousFocus?.focus({ preventScroll: true });
});
</script>

<template>
  <Teleport to="body">
    <div
      ref="overlay"
      role="dialog"
      aria-modal="true"
      aria-labelledby="plan-pricing-title"
      class="fixed inset-0 z-[1000] flex h-dvh flex-col bg-n-solid-1 text-n-slate-12 dark:bg-n-solid-3"
      @keydown="onKeydown"
    >
      <header
        class="flex shrink-0 items-center justify-between gap-4 border-b border-n-weak px-5 py-3 sm:px-10"
      >
        <div class="flex items-center gap-4">
          <img
            :src="config.logo"
            :alt="config.installationName"
            class="h-7 w-auto max-w-36 object-contain dark:hidden"
          />
          <img
            :src="config.logoDark || config.logo"
            :alt="config.installationName"
            class="hidden h-7 w-auto max-w-36 object-contain dark:block"
          />
          <span class="border-s border-n-weak ps-4 text-sm text-n-slate-11">{{
            t('PLAN_CATALOG.COMPARE')
          }}</span>
        </div>
        <Button
          icon="i-lucide-x"
          variant="ghost"
          color="slate"
          class="!size-11 shrink-0"
          :aria-label="t('PLAN_CATALOG.CLOSE')"
          @click="close"
        />
      </header>
      <div
        class="min-h-0 flex-1 overflow-y-auto overscroll-contain p-5 sm:p-10"
      >
        <div class="mx-auto max-w-[90rem] space-y-8">
          <div class="space-y-4">
            <p
              class="m-0 text-xs font-medium uppercase tracking-widest text-n-blue-11"
            >
              {{ t('PLAN_CATALOG.EYEBROW') }}
            </p>
            <h1
              id="plan-pricing-title"
              class="m-0 text-3xl font-semibold leading-tight sm:text-4xl"
            >
              {{ t('PLAN_CATALOG.TITLE') }}
            </h1>
            <p class="m-0 text-sm leading-6 text-n-slate-11">
              {{ t('PLAN_CATALOG.SUBTITLE') }}
            </p>
          </div>
          <PlanCatalog
            v-bind="props"
            @select="emit('select', $event)"
            @request-upgrade="emit('requestUpgrade', $event)"
            @continue="
              emit('continue', $event);
              close();
            "
          />
          <section
            class="space-y-6 rounded-2xl border border-n-weak bg-n-slate-2 p-6 sm:p-8"
          >
            <h2 class="m-0 text-heading-1">{{ t('PLAN_CATALOG.AFTER') }}</h2>
            <p class="text-sm text-n-slate-11">
              {{ t('PLAN_CATALOG.AFTER_SUB') }}
            </p>
            <div class="grid gap-6 md:grid-cols-3">
              <div v-for="step in 3" :key="step" class="space-y-3">
                <span
                  :class="
                    step === 2 ? 'i-woot-captain' : 'i-lucide-circle-check'
                  "
                  class="size-6 text-n-blue-11"
                  aria-hidden="true"
                />
                <h3 class="m-0 text-base font-medium">
                  {{ t(`PLAN_CATALOG.NEXT.${step}.TITLE`) }}
                </h3>
                <p class="m-0 text-sm leading-6 text-n-slate-11">
                  {{ t(`PLAN_CATALOG.NEXT.${step}.TEXT`) }}
                </p>
              </div>
            </div>
          </section>
          <section class="space-y-5 py-6">
            <h2 class="m-0 text-heading-1">{{ t('PLAN_CATALOG.FAQ') }}</h2>
            <div
              v-for="item in 4"
              :key="item"
              class="border-b border-n-weak pb-5"
            >
              <h3 class="text-base font-medium">
                {{ t(`PLAN_CATALOG.QUESTIONS.${item}.TITLE`) }}
              </h3>
              <p class="mb-0 text-sm leading-6 text-n-slate-11">
                {{ t(`PLAN_CATALOG.QUESTIONS.${item}.TEXT`) }}
              </p>
            </div>
          </section>
          <div class="flex justify-center pb-8">
            <Button
              :label="t('PLAN_CATALOG.BACK')"
              variant="outline"
              @click="close"
            />
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>
