<!-- DEPRECIATED -->
<!-- TODO: Replace this banner component with NextBanner "app/javascript/dashboard/components-next/banner/Banner.vue" -->
<script>
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    NextButton,
  },
  props: {
    bannerMessage: {
      type: String,
      default: '',
    },
    hrefLink: {
      type: String,
      default: '',
    },
    hrefLinkText: {
      type: String,
      default: '',
    },
    hasActionButton: {
      type: Boolean,
      default: false,
    },
    actionButtonVariant: {
      type: String,
      default: 'faded',
    },
    actionButtonLabel: {
      type: String,
      default: '',
    },
    actionButtonIcon: {
      type: String,
      default: 'i-lucide-arrow-right',
    },
    colorScheme: {
      type: String,
      default: '',
    },
    hasCloseButton: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['primaryAction', 'close'],
  computed: {
    bannerClasses() {
      const classList = [this.colorScheme];

      if (this.hasActionButton || this.hasCloseButton) {
        classList.push('has-button');
      }
      return classList;
    },
    // TODO - Remove this method when we standardize
    // the button color and variant names
    getButtonColor() {
      const colorMap = {
        primary: 'blue',
        secondary: 'blue',
        alert: 'ruby',
        warning: 'amber',
      };

      return colorMap[this.colorScheme] || 'blue';
    },
  },
  methods: {
    onClick(e) {
      this.$emit('primaryAction', e);
    },
    onClickClose(e) {
      this.$emit('close', e);
    },
  },
};
</script>

<template>
  <div
    class="flex flex-wrap items-center justify-center min-h-12 h-auto gap-x-4 gap-y-2 px-4 py-2.5 text-xs banner woot-banner shadow-sm"
    :class="bannerClasses"
  >
    <span class="banner-message">
      {{ bannerMessage }}
      <a
        v-if="hrefLink"
        :href="hrefLink"
        rel="noopener noreferrer nofollow"
        target="_blank"
      >
        {{ hrefLinkText }}
      </a>
    </span>
    <div v-if="hasActionButton || hasCloseButton" class="actions">
      <NextButton
        v-if="hasActionButton"
        xs
        :icon="actionButtonIcon"
        :variant="actionButtonVariant"
        :color="getButtonColor"
        :label="actionButtonLabel"
        @click="onClick"
      />
      <NextButton
        v-if="hasCloseButton"
        xs
        variant="ghost"
        icon="i-lucide-circle-x"
        :color="getButtonColor"
        :label="$t('GENERAL_SETTINGS.DISMISS')"
        @click="onClickClose"
      />
    </div>
  </div>
</template>

<style lang="scss" scoped>
.banner {
  &.primary {
    @apply bg-n-brand text-white;
  }

  &.secondary {
    @apply bg-n-solid-1 dark:bg-n-solid-3 text-n-slate-12 border border-n-weak;
    a {
      @apply text-n-slate-12;
    }
  }

  &.alert {
    @apply bg-n-ruby-3 text-n-ruby-12 border border-n-ruby-6;

    a {
      @apply text-n-ruby-12;
    }
  }

  &.warning {
    @apply bg-n-amber-3 text-n-amber-12 border border-n-amber-6;
    a {
      @apply text-n-amber-12;
    }
  }

  &.gray {
    @apply text-n-gray-10 dark:text-n-gray-10;
  }

  a {
    @apply ml-1 underline text-xs whitespace-nowrap;
    color: inherit;
  }

  .banner-message {
    @apply inline text-center leading-snug;
  }

  .actions {
    @apply flex gap-1 shrink-0;
  }
}
</style>
