<script setup>
import BackButton from 'dashboard/components/widgets/BackButton.vue';

defineProps({
  headerTitle: {
    required: true,
    type: String,
  },
  headerDescription: {
    type: String,
    default: '',
  },
  hasBackButton: {
    type: Boolean,
    default: false,
  },
});
</script>

<template>
  <section class="flex flex-col gap-1 pt-6 pb-5">
    <div v-if="hasBackButton">
      <BackButton compact />
    </div>
    <div class="flex flex-wrap justify-between w-full gap-5">
      <div class="flex flex-col gap-2 min-w-0 flex-1 basis-full sm:basis-64">
        <div class="flex flex-col gap-3 items-start">
          <span
            class="text-heading-1 text-n-slate-12 min-h-10 flex items-center max-w-full"
          >
            <span class="min-w-0 break-words">{{ headerTitle }}</span>
          </span>
          <p
            v-if="headerDescription"
            class="text-n-slate-11 mb-0 line-clamp-5 sm:line-clamp-none text-body-main"
          >
            {{ headerDescription }}
          </p>
        </div>
      </div>
      <div
        class="flex flex-wrap items-start gap-3 min-w-0 max-w-full sm:shrink-0 [&>*]:min-w-0 [&>*]:max-w-full [&>button]:!h-auto [&>button]:min-h-8 [&>button]:max-w-full [&>button]:py-1.5 [&>button>span]:whitespace-normal [&>button>span]:break-words [&>div>button]:!h-auto [&>div>button]:min-h-8 [&>div>button]:max-w-full [&>div>button]:py-1.5 [&>div>button>span]:whitespace-normal [&>div>button>span]:break-words"
      >
        <slot />
      </div>
    </div>
  </section>
</template>
