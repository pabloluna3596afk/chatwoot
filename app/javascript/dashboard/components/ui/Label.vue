<script>
import { getContrastingTextColor } from '@chatwoot/utils';
import { tintStylesFromHex } from 'dashboard/helper/colorHelper';

export default {
  props: {
    selectable: { type: Boolean, default: false },
    title: {
      type: String,
      required: true,
    },
    description: {
      type: String,
      default: '',
    },
    href: {
      type: String,
      default: '',
    },
    bgColor: {
      type: String,
      default: '',
    },
    small: {
      type: Boolean,
      default: false,
    },
    showClose: {
      type: Boolean,
      default: false,
    },
    icon: {
      type: String,
      default: '',
    },
    color: {
      type: String,
      default: '',
    },
    colorScheme: {
      type: String,
      default: '',
    },
    variant: {
      type: String,
      default: '',
    },
  },
  emits: ['remove', 'select'],
  computed: {
    isTintVariant() {
      return ['smooth', 'dashed'].includes(this.variant);
    },
    tintStyles() {
      if (!this.isTintVariant || !this.color) return {};
      return tintStylesFromHex(this.color);
    },
    textColor() {
      if (this.isTintVariant) {
        return this.tintStyles.color || this.color || '';
      }
      return this.color || getContrastingTextColor(this.bgColor);
    },
    labelClass() {
      return `label ${this.colorScheme} ${this.variant} ${
        this.small ? 'small' : ''
      }`;
    },
    labelStyle() {
      if (this.isTintVariant && Object.keys(this.tintStyles).length) {
        return {
          backgroundColor: this.tintStyles.backgroundColor,
          borderColor: this.tintStyles.borderColor,
          color: this.tintStyles.color,
        };
      }
      if (this.bgColor) {
        return {
          background: this.bgColor,
          color: this.textColor,
          border: `1px solid ${this.bgColor}`,
        };
      }
      return {};
    },
    anchorStyle() {
      if (this.isTintVariant && this.textColor) {
        return { color: this.textColor };
      }
      if (this.bgColor) {
        return { color: this.textColor };
      }
      return {};
    },
  },
  methods: {
    onSelect(event) {
      if (!this.selectable) return;
      event.stopPropagation();
      this.$emit('select', this.title);
    },
    onClick() {
      this.$emit('remove', this.title);
    },
  },
};
</script>

<template>
  <div
    class="inline-flex min-w-0 max-w-full ltr:mr-1 rtl:ml-1 mb-1"
    :class="labelClass"
    :style="labelStyle"
    :title="description || title"
  >
    <span v-if="icon" class="label-action--button">
      <fluent-icon :icon="icon" size="12" class="label--icon cursor-pointer" />
    </span>
    <component
      :is="selectable ? 'button' : 'span'"
      v-if="!href"
      :type="selectable ? 'button' : undefined"
      class="min-w-0 truncate text-start"
      :class="{ 'cursor-pointer': selectable }"
      :title="title"
      @click="onSelect"
    >
      {{ title }}
    </component>
    <a v-else :href="href" :style="anchorStyle">{{ title }}</a>
    <button
      v-if="showClose"
      class="label-close--button p-0"
      :style="{ color: textColor }"
      @click="onClick"
    >
      <fluent-icon icon="dismiss" size="12" class="close--icon" />
    </button>
  </div>
</template>

<style scoped lang="scss">
.label {
  @apply items-center font-medium text-xs rounded-[4px] gap-1 p-1 bg-n-slate-3 text-n-slate-12 border border-solid border-n-strong h-6;

  &.small {
    @apply text-xs py-0.5 px-1 leading-tight h-5;
  }

  &.small .label--icon,
  &.small .close--icon {
    @apply text-[0.5rem];
  }

  a {
    @apply text-xs;
    &:hover {
      @apply underline;
    }
  }

  /* Color Schemes */
  &.primary {
    @apply bg-n-blue-5 text-n-blue-12 border border-solid border-n-blue-7;

    a {
      @apply text-n-blue-12;
    }
  }
  &.secondary {
    @apply bg-n-slate-5 text-n-slate-12 border border-solid border-n-slate-7;

    a {
      @apply text-n-slate-12;
    }
  }
  &.success {
    @apply bg-n-teal-5 text-n-teal-12 border border-solid border-n-teal-7;

    a {
      @apply text-n-teal-12;
    }
  }
  &.alert {
    @apply bg-n-ruby-5 text-n-ruby-12 border border-solid border-n-ruby-7;

    a {
      @apply text-n-ruby-12;
    }
  }
  &.warning {
    @apply bg-n-amber-5 text-n-amber-12 border border-solid border-n-amber-7;

    a {
      @apply text-n-amber-12;
    }
  }

  &.smooth {
    @apply bg-transparent border border-solid;
  }

  &.dashed {
    @apply bg-transparent border border-dashed;
  }
}

.label-close--button {
  @apply text-n-slate-11 -mb-0.5 rounded-sm cursor-pointer flex items-center justify-center hover:bg-n-slate-3;

  svg {
    @apply text-n-slate-11;
  }
}

.label-action--button {
  @apply flex mr-1;
}
</style>
