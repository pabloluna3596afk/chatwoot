<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import Avatar from 'next/avatar/Avatar.vue';

// Who made an appointment: the assistant, with its photo inside the Captain ring, or the person.
const props = defineProps({
  creator: {
    type: Object,
    default: null,
  },
  size: {
    type: Number,
    default: 18,
  },
});

const { t } = useI18n();

const isCaptain = computed(() => props.creator?.type === 'captain');
const label = computed(() =>
  t('CONVERSATION_SIDEBAR.CALENDAR.CREATED_BY', { name: props.creator?.name })
);
</script>

<template>
  <span
    v-if="creator?.name"
    v-tooltip.top="label"
    class="inline-flex shrink-0 rounded-full"
    :class="isCaptain ? 'ring-2 ring-n-teal-9' : ''"
    :data-testid="isCaptain ? 'creator-captain' : 'creator-user'"
  >
    <Avatar
      :name="creator.name"
      :src="creator.thumbnail"
      :size="size"
      hide-offline-status
      rounded-full
    />
  </span>
</template>
