<script setup>
import { useMapGetter } from 'dashboard/composables/store';
import { useBranding } from 'shared/composables/useBranding';
import loginHero from 'assets/images/auth/login-hero.png';

defineProps({
  title: { type: String, required: true },
  subtitle: { type: String, required: true },
  scrollable: Boolean,
});

const globalConfig = useMapGetter('globalConfig/get');
const { replaceInstallationName } = useBranding();
</script>

<template>
  <main
    class="flex min-h-screen w-full bg-n-solid-1 dark:bg-n-background"
    :class="{ 'h-dvh !min-h-0 overflow-hidden': scrollable }"
  >
    <aside class="relative hidden min-h-screen w-1/2 overflow-hidden lg:block">
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
        class="absolute inset-x-0 bottom-0 h-2/5 bg-gradient-to-t from-n-black/90 via-n-black/70 via-80% to-transparent"
      />
      <img
        :src="globalConfig.logoDark || globalConfig.logo"
        :alt="globalConfig.installationName"
        class="absolute start-10 top-10 z-10 h-8 w-auto max-w-52 object-contain xl:start-14 xl:top-14"
      />
      <div
        class="absolute inset-x-0 bottom-10 px-10 text-start text-white xl:bottom-14 xl:px-14"
      >
        <p
          data-testid="auth-marketing-title"
          class="max-w-lg text-4xl xl:text-5xl 2xl:text-6xl font-serif font-normal leading-tight tracking-tight text-white"
        >
          {{ replaceInstallationName(title) }}
        </p>
        <p class="mt-4 max-w-md text-base leading-7 text-white xl:text-lg">
          {{ replaceInstallationName(subtitle) }}
        </p>
      </div>
    </aside>

    <section
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
