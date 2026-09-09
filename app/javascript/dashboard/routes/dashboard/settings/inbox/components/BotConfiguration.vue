<script>
import { mapGetters } from 'vuex';
import { useAlert } from 'dashboard/composables';
import SettingsFieldSection from 'dashboard/components-next/Settings/SettingsFieldSection.vue';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import NextButton from 'dashboard/components-next/button/Button.vue';
import SelectInput from 'dashboard/components-next/select/Select.vue';
import RadioCard from 'dashboard/components-next/radioCard/RadioCard.vue';
import BusinessDay from './BusinessDay.vue';
import {
  timeSlotParse,
  timeSlotTransform,
  defaultTimeSlot,
} from '../helpers/businessHour';

const SCHEDULE_MODES = ['always', 'outside_inbox_hours', 'own_hours'];

export default {
  components: {
    LoadingState,
    SettingsFieldSection,
    NextButton,
    SelectInput,
    RadioCard,
    BusinessDay,
  },
  props: {
    inbox: {
      type: Object,
      default: () => ({}),
    },
  },
  data() {
    return {
      selectedAgentBotId: null,
      scheduleMode: 'always',
      timeSlots: [...defaultTimeSlot],
      dayNames: {
        0: 'Sunday',
        1: 'Monday',
        2: 'Tuesday',
        3: 'Wednesday',
        4: 'Thursday',
        5: 'Friday',
        6: 'Saturday',
      },
    };
  },
  computed: {
    ...mapGetters({
      agentBots: 'agentBots/getBots',
      uiFlags: 'agentBots/getUIFlags',
    }),
    currentInboxId() {
      return this.inbox?.id || this.$route.params.inboxId;
    },
    activeAgentBot() {
      return this.$store.getters['agentBots/getActiveAgentBot'](
        this.currentInboxId
      );
    },
    agentBotSchedule() {
      return this.$store.getters['agentBots/getAgentBotSchedule'](
        this.currentInboxId
      );
    },
    // Deactivated bots (see AGENT_BOTS.DEACTIVATE) drop out of "assign a new
    // bot" pickers — except the one already assigned here, so this screen
    // still shows what's connected instead of silently looking empty.
    assignableAgentBots() {
      return this.agentBots.filter(
        bot => bot.active !== false || bot.id === this.selectedAgentBotId
      );
    },
  },
  watch: {
    activeAgentBot() {
      this.selectedAgentBotId = this.activeAgentBot.id;
    },
    agentBotSchedule() {
      this.applyScheduleDefaults();
    },
  },
  mounted() {
    this.fetchBotData();
  },

  methods: {
    fetchBotData() {
      this.$store.dispatch('agentBots/get');
      this.$store.dispatch('agentBots/fetchAgentBotInbox', this.currentInboxId);
    },
    applyScheduleDefaults() {
      const { scheduleMode, botWorkingHours } = this.agentBotSchedule;
      this.scheduleMode = scheduleMode || 'always';
      this.timeSlots = botWorkingHours?.length
        ? timeSlotParse(botWorkingHours)
        : [...defaultTimeSlot];
    },
    onSlotUpdate(slotIndex, slotData) {
      this.timeSlots = this.timeSlots.map(item =>
        item.day === slotIndex ? slotData : item
      );
    },
    async updateActiveAgentBot() {
      try {
        await this.$store.dispatch('agentBots/setAgentBotInbox', {
          inboxId: this.inbox.id,
          // Added this to make sure that empty values are not sent to the API
          botId: this.selectedAgentBotId ? this.selectedAgentBotId : undefined,
          scheduleMode: this.scheduleMode,
          botWorkingHours:
            this.scheduleMode === 'own_hours'
              ? timeSlotTransform(this.timeSlots)
              : undefined,
        });
        useAlert(this.$t('AGENT_BOTS.BOT_CONFIGURATION.SUCCESS_MESSAGE'));
      } catch (error) {
        useAlert(this.$t('AGENT_BOTS.BOT_CONFIGURATION.ERROR_MESSAGE'));
      }
    },
    async disconnectBot() {
      try {
        await this.$store.dispatch('agentBots/disconnectBot', {
          inboxId: this.inbox.id,
        });
        useAlert(
          this.$t('AGENT_BOTS.BOT_CONFIGURATION.DISCONNECTED_SUCCESS_MESSAGE')
        );
      } catch (error) {
        useAlert(
          error?.message ||
            this.$t('AGENT_BOTS.BOT_CONFIGURATION.DISCONNECTED_ERROR_MESSAGE')
        );
      }
    },
  },
  SCHEDULE_MODES,
};
</script>

<template>
  <div class="mx-6 max-w-4xl">
    <LoadingState v-if="uiFlags.isFetching || uiFlags.isFetchingAgentBot" />
    <form v-else @submit.prevent="updateActiveAgentBot">
      <SettingsFieldSection
        :label="$t('AGENT_BOTS.BOT_CONFIGURATION.TITLE')"
        :help-text="$t('AGENT_BOTS.BOT_CONFIGURATION.DESC')"
        class="[&>div]:!items-start"
      >
        <SelectInput
          v-model="selectedAgentBotId"
          :placeholder="$t('AGENT_BOTS.BOT_CONFIGURATION.SELECT_PLACEHOLDER')"
          :options="
            assignableAgentBots.map(bot => ({ value: bot.id, label: bot.name }))
          "
        />
        <template #extra>
          <div v-if="selectedAgentBotId" class="mt-4 flex flex-col gap-3">
            <p class="m-0 text-sm font-medium text-n-slate-12">
              {{ $t('AGENT_BOTS.BOT_CONFIGURATION.SCHEDULE.TITLE') }}
            </p>
            <div class="grid gap-3 sm:grid-cols-3">
              <RadioCard
                v-for="mode in $options.SCHEDULE_MODES"
                :id="`bot-schedule-${mode}`"
                :key="mode"
                :label="
                  $t(
                    `AGENT_BOTS.BOT_CONFIGURATION.SCHEDULE.MODES.${mode}.LABEL`
                  )
                "
                :description="
                  $t(
                    `AGENT_BOTS.BOT_CONFIGURATION.SCHEDULE.MODES.${mode}.DESCRIPTION`
                  )
                "
                :is-active="scheduleMode === mode"
                @select="scheduleMode = mode"
              />
            </div>

            <div v-if="scheduleMode === 'own_hours'" class="mt-2 w-full">
              <table
                class="min-w-full table-auto outline outline-1 -outline-offset-1 outline-n-weak rounded-xl"
              >
                <thead>
                  <tr class="border-b border-n-weak">
                    <th
                      class="py-3 ltr:pl-4 ltr:pr-3 rtl:pl-3 rtl:pr-4 text-start text-heading-3 text-n-slate-12"
                    >
                      {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.DAY') }}
                    </th>
                    <th
                      class="py-3 ltr:pr-3 rtl:pl-3 text-start text-heading-3 text-n-slate-12"
                    >
                      {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.AVAILABILITY') }}
                    </th>
                    <th
                      class="py-3 ltr:pr-3 rtl:pl-3 text-start text-heading-3 text-n-slate-12"
                    >
                      {{ $t('INBOX_MGMT.BUSINESS_HOURS.DAY.HOURS') }}
                    </th>
                  </tr>
                </thead>
                <tbody class="divide-y divide-n-weak">
                  <BusinessDay
                    v-for="timeSlot in timeSlots"
                    :key="timeSlot.day"
                    :day-name="dayNames[timeSlot.day]"
                    :time-slot="timeSlot"
                    @update="data => onSlotUpdate(timeSlot.day, data)"
                  />
                </tbody>
              </table>
            </div>
          </div>

          <div class="grid grid-cols-1 lg:grid-cols-8 mt-3">
            <div class="col-span-1 lg:col-span-2 invisible" />
            <div class="col-span-1 lg:col-span-6 flex gap-2 mx-1">
              <NextButton
                type="submit"
                :label="$t('AGENT_BOTS.BOT_CONFIGURATION.SUBMIT')"
                :is-loading="uiFlags.isSettingAgentBot"
              />
              <NextButton
                type="button"
                :disabled="!selectedAgentBotId"
                :is-loading="uiFlags.isDisconnecting"
                faded
                ruby
                @click="disconnectBot"
              >
                {{ $t('AGENT_BOTS.BOT_CONFIGURATION.DISCONNECT') }}
              </NextButton>
            </div>
          </div>
        </template>
      </SettingsFieldSection>
    </form>
  </div>
</template>
