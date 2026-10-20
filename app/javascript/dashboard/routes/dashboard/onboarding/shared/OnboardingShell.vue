<script setup>
import { computed, onMounted, provide, ref, watch, nextTick } from 'vue';
import { useI18n } from 'vue-i18n';
import { useMapGetter } from 'dashboard/composables/store';
import AuthButton from 'v3/components/Auth/AuthButton.vue';
import { AUTH_LINK_CLASS } from 'v3/components/Auth/authStyles';

const props = defineProps({
  current: { type: Number, required: true },
  title: { type: String, required: true },
  subtitle: { type: String, default: '' },
  backTo: { type: Object, default: null },
  backDisabled: Boolean,
});
const emit = defineEmits(['back']);
const { t } = useI18n();
const config = useMapGetter('globalConfig/get');
const logoFailed = ref(false);
const logoDarkFailed = ref(false);
const logo = computed(() =>
  !logoFailed.value && config.value.logo
    ? config.value.logo
    : '/brand-assets/logo.svg'
);
const logoDark = computed(() =>
  !logoDarkFailed.value && (config.value.logoDark || config.value.logo)
    ? config.value.logoDark || config.value.logo
    : '/brand-assets/logo_dark.svg'
);
const steps = computed(() => [
  t('ONBOARDING_LAYOUT.STEPS.BUSINESS'),
  t('ONBOARDING_LAYOUT.STEPS.WHATSAPP'),
  t('ONBOARDING_LAYOUT.STEPS.ASSISTANT'),
  t('ONBOARDING_LAYOUT.STEPS.PLAN'),
]);
const scroller = ref(null);
const heading = ref(null);
provide('comboboxBoundary', scroller);
const focusHeading = () =>
  nextTick(() => {
    scroller.value.scrollTop = 0;
    heading.value.focus({ preventScroll: true });
  });
onMounted(focusHeading);
watch(() => props.current, focusHeading);
</script>

<template>
  <main
    class="flex h-dvh min-h-0 w-full flex-col overflow-hidden bg-n-slate-2 text-n-slate-12 [&_button.bg-n-brand]:!bg-n-blue-11 [&_button.bg-n-brand]:!text-n-solid-1"
  >
    <header
      class="shrink-0 border-b border-n-weak bg-n-solid-1 px-5 py-4 sm:px-8 dark:bg-n-solid-3"
    >
      <div class="mx-auto w-full max-w-[60rem] space-y-4">
        <div class="flex items-center justify-between gap-4">
          <img
            :src="logo"
            :alt="config.installationName"
            class="h-7 w-auto max-w-40 shrink-0 object-contain dark:hidden"
            @error="logoFailed = true"
          />
          <img
            :src="logoDark"
            :alt="config.installationName"
            class="hidden h-7 w-auto max-w-40 shrink-0 object-contain dark:block"
            @error="logoDarkFailed = true"
          />
          <p
            class="m-0 hidden flex-1 border-s border-n-weak ps-4 text-sm text-n-slate-11 sm:block"
          >
            {{ t('ONBOARDING_LAYOUT.TAGLINE') }}
          </p>
          <p class="m-0 shrink-0 text-sm text-n-slate-11" aria-live="polite">
            {{ t('ONBOARDING_LAYOUT.STEP', { current, total: 4 }) }}
          </p>
        </div>
        <ol
          class="m-0 grid list-none grid-cols-4 gap-2 p-0 sm:gap-4"
          :aria-label="t('ONBOARDING_AUTH.PROGRESS')"
        >
          <li
            v-for="(step, index) in steps"
            :key="step"
            :aria-current="index + 1 === current ? 'step' : undefined"
            class="min-w-0 space-y-2 text-xs sm:text-sm"
            :class="index + 1 <= current ? 'text-n-blue-11' : 'text-n-slate-11'"
          >
            <span>{{
              t('ONBOARDING_LAYOUT.STEP_LABEL', {
                number: index + 1,
                name: step,
              })
            }}</span>
            <span
              class="block h-1.5 rounded-full"
              :class="index + 1 <= current ? 'bg-n-blue-9' : 'bg-n-slate-5'"
              aria-hidden="true"
            />
          </li>
        </ol>
        <span
          role="progressbar"
          class="sr-only"
          :aria-label="t('ONBOARDING_AUTH.PROGRESS')"
          :aria-valuenow="current"
          :aria-valuemin="1"
          :aria-valuemax="4"
          :aria-valuetext="steps[current - 1]"
        />
      </div>
    </header>
    <div
      ref="scroller"
      class="min-h-0 flex-1 overflow-y-auto overscroll-y-contain px-5 py-5 sm:px-8 sm:py-6 [@media(max-height:50rem)]:!py-4"
      data-testid="onboarding-scroll-content"
    >
      <div class="mx-auto w-full max-w-[60rem]">
        <header class="mb-5 space-y-2">
          <div
            v-if="$slots.eyebrow"
            class="flex items-center gap-2 text-xs font-medium uppercase tracking-widest text-n-blue-11 [@media(max-height:50rem)]:hidden"
          >
            <slot name="eyebrow" />
          </div>
          <h1
            ref="heading"
            tabindex="-1"
            class="m-0 text-2xl font-semibold leading-tight tracking-tight outline-none sm:text-3xl"
          >
            {{ title }}
          </h1>
          <p v-if="subtitle" class="m-0 text-base leading-6 text-n-slate-11">
            {{ subtitle }}
          </p>
          <slot name="intro" />
        </header>
        <slot />
      </div>
    </div>
    <footer
      class="shrink-0 border-t border-n-weak bg-n-solid-1 px-5 pt-3 pb-[max(0.75rem,env(safe-area-inset-bottom))] sm:px-8 dark:bg-n-solid-3"
    >
      <div
        class="mx-auto flex w-full max-w-[60rem] items-center justify-between gap-4"
      >
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
          />{{ t('ONBOARDING_AUTH.BACK') }}
        </RouterLink>
        <AuthButton
          v-else-if="$slots.back"
          variant="secondary"
          class="!w-auto !border-0 !bg-transparent !px-0"
          :disabled="backDisabled"
          @click="emit('back')"
        >
          <slot name="back" />
        </AuthButton>
        <p v-else class="m-0 hidden text-sm text-n-slate-11 sm:block">
          {{ t('ONBOARDING_LAYOUT.FOOTNOTE') }}
        </p>
        <div
          class="ms-auto flex w-full max-w-sm flex-col items-stretch gap-2 sm:w-auto sm:min-w-44"
        >
          <slot name="footer" />
        </div>
      </div>
    </footer>
  </main>
</template>
