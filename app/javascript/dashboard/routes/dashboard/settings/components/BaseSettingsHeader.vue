<script setup>
import { useSlots } from 'vue';
import CustomBrandPolicyWrapper from 'dashboard/components/CustomBrandPolicyWrapper.vue';
import { getHelpUrlForFeature } from '../../../../helper/featureHelper';
import BackButton from '../../../../components/widgets/BackButton.vue';
import Icon from 'dashboard/components-next/icon/Icon.vue';
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({
  title: {
    type: String,
    required: true,
  },
  description: {
    type: String,
    default: '',
  },
  linkText: {
    type: String,
    default: '',
  },
  featureName: {
    type: String,
    default: '',
  },
  backButtonLabel: {
    type: String,
    default: '',
  },
  searchPlaceholder: {
    type: String,
    default: '',
  },
});

const slots = useSlots();

const searchQuery = defineModel('searchQuery', { type: String, default: '' });

const helpURL = getHelpUrlForFeature(props.featureName);
</script>

<template>
  <div class="flex flex-col items-start w-full">
    <BackButton
      v-if="backButtonLabel"
      compact
      :button-label="backButtonLabel"
      class="my-1"
    />
    <div
      v-if="title"
      class="flex items-center justify-between w-full gap-4 min-h-8 mb-2"
    >
      <slot name="title">
        <h1 class="min-w-0 break-words text-heading-1 text-n-slate-12">
          {{ title }}
        </h1>
      </slot>
    </div>
    <div
      v-if="
        description || $slots.description || linkText || helpURL || $slots.meta
      "
      class="flex flex-col w-full gap-1.5 text-n-slate-11"
    >
      <p
        v-if="description || $slots.description"
        class="mb-0 line-clamp-5 sm:line-clamp-none max-w-3xl text-body-main"
      >
        <slot name="description">{{ description }}</slot>
      </p>
      <CustomBrandPolicyWrapper :show-on-custom-branded-instance="false">
        <a
          v-if="helpURL && linkText"
          :href="helpURL"
          target="_blank"
          rel="noopener noreferrer"
          class="items-center hidden gap-1 text-sm font-medium sm:inline-flex w-fit text-n-blue-11 hover:underline mb-2"
        >
          {{ linkText }}
          <Icon
            icon="i-lucide-chevron-right"
            class="flex-shrink-0 text-n-blue-11 size-4"
          />
        </a>
      </CustomBrandPolicyWrapper>
      <slot name="meta" />
    </div>
  </div>
  <div
    v-if="searchPlaceholder || slots.actions || slots.tabs"
    class="gap-3 flex flex-wrap justify-between sm:mt-4 min-w-0"
  >
    <div
      v-if="slots.tabs || searchPlaceholder"
      class="flex flex-wrap items-center gap-3 min-w-0 w-full sm:w-auto"
    >
      <slot name="tabs" />
      <Input
        v-if="searchPlaceholder"
        v-model="searchQuery"
        :placeholder="searchPlaceholder"
        :aria-label="searchPlaceholder"
        class="group w-full sm:w-56 min-w-0 [&>input]:ltr:!pl-8 [&>input]:rtl:!pr-8 [&>input]:!rounded-[0.625rem]"
        size="sm"
        type="search"
      >
        <template #prefix>
          <Icon
            icon="i-lucide-search"
            class="absolute top-1/2 -translate-y-1/2 text-n-slate-11 group-focus-within:text-n-brand size-3.5 ltr:left-2.5 rtl:right-2.5"
          />
        </template>
      </Input>
    </div>
    <div
      class="flex flex-wrap items-center gap-3 min-w-0 max-w-full [&>a]:min-w-0 [&>a]:max-w-full [&>button]:!h-auto [&>button]:min-h-8 [&>button]:py-1.5 [&>button>span]:whitespace-normal [&>button>span]:break-words [&>a>button]:!h-auto [&>a>button]:min-h-8 [&>a>button]:max-w-full [&>a>button]:py-1.5 [&>a>button>span]:whitespace-normal [&>a>button>span]:break-words"
      :class="{ 'flex-row-reverse sm:flex-row': !slots.tabs }"
    >
      <slot name="count" />
      <div
        v-if="slots.count && slots.actions"
        class="hidden sm:block w-px h-3 rounded-lg bg-n-weak ltr:ml-1 ltr:mr-2 rtl:ml-2 rtl:mr-1 flex-shrink-0"
      />
      <slot name="actions" />
    </div>
  </div>
</template>
