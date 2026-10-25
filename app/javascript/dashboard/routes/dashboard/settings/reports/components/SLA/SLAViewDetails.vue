<script>
import SLAPopoverCard from 'dashboard/components/widgets/conversation/components/SLAPopoverCard.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';

export default {
  components: {
    SLAPopoverCard,
    NextButton,
  },
  props: {
    mobile: {
      type: Boolean,
      default: false,
    },
    slaEvents: {
      type: Array,
      default: () => [],
    },
  },

  data() {
    return {
      showSlaPopoverCard: false,
    };
  },

  methods: {
    closeSlaEvents() {
      this.showSlaPopoverCard = false;
    },
    openSlaEvents() {
      this.showSlaPopoverCard = !this.showSlaPopoverCard;
    },
  },
};
</script>

<template>
  <div
    v-on-clickaway="closeSlaEvents"
    class="flex items-center col-span-2 text-n-slate-11 justify-end"
    :class="{ 'min-h-11 justify-start': mobile }"
  >
    <div class="relative">
      <NextButton
        link
        slate
        type="button"
        :class="{ 'min-h-11': mobile }"
        :label="$t('SLA_REPORTS.TABLE.VIEW_DETAILS')"
        @click="openSlaEvents"
      />
      <SLAPopoverCard
        v-if="showSlaPopoverCard"
        :sla-missed-events="slaEvents"
        class="right-0"
      />
    </div>
  </div>
</template>
