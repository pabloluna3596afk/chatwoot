<script>
import TableFooter from 'dashboard/components/widgets/TableFooter.vue';
import TableHeaderCell from 'dashboard/components/widgets/TableHeaderCell.vue';
import SLAReportItem from './SLAReportItem.vue';
import Spinner from 'shared/components/Spinner.vue';
import ListCard from 'dashboard/components-next/ListCard/ListCard.vue';
import InfoChip from 'dashboard/components-next/ListCard/InfoChip.vue';
import CardLabels from 'dashboard/components/widgets/conversation/conversationCardComponents/CardLabels.vue';
import SLAViewDetails from './SLAViewDetails.vue';
export default {
  name: 'SLATable',
  components: {
    SLAReportItem,
    TableFooter,
    Spinner,
    TableHeaderCell,
    ListCard,
    InfoChip,
    CardLabels,
    SLAViewDetails,
  },
  props: {
    slaReports: {
      type: Array,
      default: () => [],
    },
    totalCount: {
      type: Number,
      default: 0,
    },
    currentPage: {
      type: Number,
      default: 1,
    },
    pageSize: {
      type: Number,
      default: 25,
    },
    isLoading: {
      type: Boolean,
      default: false,
    },
  },
  emits: ['pageChange'],
  data() {
    return {
      pageNo: 1,
    };
  },
  computed: {
    shouldShowFooter() {
      return this.currentPage === 1
        ? this.totalCount > this.pageSize
        : this.slaReports.length > 0;
    },
  },
  methods: {
    onPageChange(page) {
      this.$emit('pageChange', page);
    },
  },
};
</script>

<template>
  <div>
    <div
      class="hidden md:block min-w-full shadow outline-1 outline outline-n-container rounded-xl bg-n-solid-2 p-6"
    >
      <div
        class="grid content-center h-12 grid-cols-12 gap-4 px-6 py-0 bg-n-slate-2 rounded-md"
      >
        <TableHeaderCell
          :span="6"
          :label="$t('SLA_REPORTS.TABLE.HEADER.CONVERSATION')"
        />
        <TableHeaderCell
          :span="2"
          :label="$t('SLA_REPORTS.TABLE.HEADER.POLICY')"
        />
        <TableHeaderCell
          :span="2"
          :label="$t('SLA_REPORTS.TABLE.HEADER.AGENT')"
        />
        <TableHeaderCell :span="1" label="" />
      </div>

      <div v-if="isLoading" class="flex items-center justify-center h-32">
        <Spinner />
        <span>{{ $t('SLA_REPORTS.LOADING') }}</span>
      </div>
      <div v-else-if="slaReports.length > 0">
        <SLAReportItem
          v-for="slaReport in slaReports"
          :key="slaReport.applied_sla.id"
          :sla-name="slaReport.applied_sla.sla_name"
          :conversation="slaReport.conversation"
          :conversation-id="slaReport.conversation.id"
          :sla-events="slaReport.sla_events"
        />
      </div>
      <div v-else class="flex items-center justify-center h-32">
        {{ $t('SLA_REPORTS.NO_RECORDS') }}
      </div>
    </div>
    <div
      v-if="isLoading"
      class="flex items-center justify-center h-32 md:hidden"
    >
      <Spinner />
      <span>{{ $t('SLA_REPORTS.LOADING') }}</span>
    </div>
    <div
      v-else-if="!slaReports.length"
      class="flex items-center justify-center h-32 md:hidden"
    >
      {{ $t('SLA_REPORTS.NO_RECORDS') }}
    </div>
    <div v-else class="flex flex-col gap-3 md:hidden">
      <ListCard
        v-for="slaReport in slaReports"
        :key="slaReport.applied_sla.id"
        :title="`#${slaReport.conversation.id} ${slaReport.conversation.contact.name}`"
        :subtitle="slaReport.applied_sla.sla_name"
      >
        <template #title>
          <router-link
            :to="{
              name: 'inbox_conversation',
              params: { conversation_id: slaReport.conversation.id },
            }"
            class="text-n-slate-12 hover:underline"
          >
            {{ `#${slaReport.conversation.id}` }}
            {{ slaReport.conversation.contact.name }}
          </router-link>
        </template>
        <template #chips>
          <InfoChip>
            {{ $t('SLA_REPORTS.TABLE.HEADER.POLICY') }}
            {{ slaReport.applied_sla.sla_name }}
          </InfoChip>
          <InfoChip>
            {{ $t('SLA_REPORTS.TABLE.HEADER.AGENT') }}
            {{ slaReport.conversation.assignee?.name || '---' }}
          </InfoChip>
        </template>
        <template #after>
          <div class="mt-3 flex flex-col gap-2">
            <CardLabels
              v-if="slaReport.conversation.labels"
              :conversation-id="slaReport.conversation.id"
              :conversation-labels="
                slaReport.conversation.labels
                  .split(',')
                  .map(item => item.trim())
              "
            />
            <SLAViewDetails :sla-events="slaReport.sla_events" mobile />
          </div>
        </template>
      </ListCard>
    </div>
    <TableFooter
      v-if="shouldShowFooter"
      :current-page="currentPage"
      :total-count="totalCount"
      :page-size="pageSize"
      @page-change="onPageChange"
    />
  </div>
</template>
