<script setup>
import { useMapGetter } from 'dashboard/composables/store';
import { useBranding } from 'shared/composables/useBranding';
import loginHero from 'assets/images/auth/login-hero.png';
import AuthFooterBar from './AuthFooterBar.vue';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, required: true },
  scrollable: Boolean,
  onboarding: Boolean,
});

const globalConfig = useMapGetter('globalConfig/get');
const { replaceInstallationName } = useBranding();
</script>

<template>
  <main
    class="flex min-h-screen w-full bg-n-solid-1 dark:bg-n-background"
    :class="{ 'h-dvh !min-h-0 overflow-hidden': scrollable || onboarding }"
  >
    <aside
      class="relative hidden min-h-screen w-1/2 overflow-hidden lg:block"
      :class="{ '!min-h-0': onboarding }"
    >
      <img
        :src="loginHero"
        alt=""
        aria-hidden="true"
        class="absolute inset-0 size-full object-cover object-right"
      />
      <div
        class="absolute inset-x-0 top-0 h-1/5 bg-gradient-to-b from-n-black/70 to-transparent"
      />
      <div
        class="absolute inset-x-0 bottom-0 bg-gradient-to-t to-transparent"
        :class="
          onboarding
            ? 'h-3/5 from-n-black via-n-black/90'
            : 'h-2/5 from-n-black/90 via-n-black/70 via-80%'
        "
      />
      <img
        :src="globalConfig.logoDark || globalConfig.logo"
        :alt="globalConfig.installationName"
        class="absolute start-10 top-10 z-10 h-8 w-auto max-w-52 object-contain xl:start-14 xl:top-14"
      />
      <div
        class="absolute inset-x-0 text-start text-white"
        :class="
          onboarding
            ? 'bottom-12 px-10 xl:px-12'
            : 'bottom-10 px-10 xl:bottom-14 xl:px-14'
        "
      >
        <component
          :is="onboarding ? 'p' : 'h1'"
          data-testid="auth-marketing-title"
          class="max-w-lg font-serif font-normal leading-tight tracking-tight text-white"
          :class="
            onboarding
              ? 'text-balance text-4xl 2xl:text-5xl'
              : 'text-4xl xl:text-5xl 2xl:text-6xl'
          "
        >
          {{ replaceInstallationName(title) }}
        </component>
        <p class="mt-4 max-w-md text-base leading-7 text-white xl:text-lg">
          {{ replaceInstallationName(subtitle) }}
        </p>
      </div>
    </aside>

    <section
      v-if="onboarding"
      class="flex h-full min-h-0 min-w-0 w-full flex-col px-6 pt-6 pb-[max(1.5rem,env(safe-area-inset-bottom))] sm:px-10 lg:w-1/2 xl:px-12"
      data-testid="onboarding-column"
    >
      <div
        class="mx-auto my-auto flex max-h-full min-h-0 w-full max-w-[30rem] flex-col"
      >
        <!-- The footer reserves its actual height in this flex column. The
             scroller's extra 1rem keeps the final link clear of the footer. -->
        <div
          class="-mx-2 min-h-0 overflow-y-auto overscroll-y-contain px-2 pt-1 pb-4"
          data-testid="onboarding-scroll-content"
        >
          <div class="mb-8 flex justify-center lg:hidden">
            <img
              :src="globalConfig.logo"
              :alt="globalConfig.installationName"
              class="h-8 w-auto max-w-52 object-contain dark:hidden"
            />
            <img
              :src="globalConfig.logoDark || globalConfig.logo"
              :alt="globalConfig.installationName"
              class="hidden h-8 w-auto max-w-52 object-contain dark:block"
            />
          </div>
          <div
            class="min-w-0 motion-safe:animate-fade-in-up motion-safe:[animation-duration:200ms]"
          >
            <slot />
          </div>
        </div>
        <AuthFooterBar v-if="$slots.footer">
          <slot name="footer" />
        </AuthFooterBar>
      </div>
    </section>
    <section
      v-else
      class="flex min-h-screen min-w-0 w-full flex-col px-6 py-10 sm:px-12 lg:w-1/2 lg:px-12 xl:px-16"
      :class="{ '!min-h-0 !py-0': scrollable }"
    >
      <div
        class="mx-auto flex w-full max-w-[30rem] flex-1 flex-col justify-center"
        :class="{
          'min-h-0 !justify-start overflow-y-auto py-6': scrollable,
        }"
      >
        <div class="mb-10 flex justify-center lg:hidden">
          <img
            :src="globalConfig.logo"
            :alt="globalConfig.installationName"
            class="h-8 w-auto max-w-52 object-contain dark:hidden"
          />
          <img
            :src="globalConfig.logoDark || globalConfig.logo"
            :alt="globalConfig.installationName"
            class="hidden h-8 w-auto max-w-52 object-contain dark:block"
          />
        </div>

        <slot />
      </div>
      <div
        v-if="$slots.footer"
        class="mx-auto w-full max-w-[30rem] shrink-0 bg-n-solid-1 pt-3 pb-6 dark:bg-n-background"
      >
        <slot name="footer" />
      </div>
    </section>
  </main>
</template>
