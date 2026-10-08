<script setup>
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

defineProps({
  columns: { type: Array, required: true },
  items: { type: Array, required: true },
  total: { type: Number, required: true },
  page: { type: Number, required: true },
  pageSize: { type: Number, required: true },
  perPageOptions: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:page', 'update:pageSize', 'open']);
</script>

<template>
  <div>
    <div class="overflow-x-auto">
      <BaseTable
        :headers="['', ...columns.map(column => column.label)]"
        :items="items"
      >
        <template #row>
          <BaseTableRow
            v-for="item in items"
            :key="item.key || item.id"
            :item="item"
            tabindex="0"
            class="cursor-pointer hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-n-brand"
            @click="emit('open', item)"
            @keydown.enter.self="emit('open', item)"
          >
            <BaseTableCell>
              <span
                class="grid size-8 place-items-center rounded-lg border border-n-strong bg-n-alpha-2"
              >
                <ChannelIcon
                  :inbox="{ channel_type: 'Channel::Whatsapp' }"
                  class="size-5"
                />
              </span>
            </BaseTableCell>
            <BaseTableCell v-for="column in columns" :key="column.key">
              <slot :name="column.key" :item="item">
                {{ item[column.key] }}
              </slot>
            </BaseTableCell>
          </BaseTableRow>
        </template>
      </BaseTable>
    </div>
    <PaginationFooter
      v-if="total"
      :current-page="page"
      :total-items="total"
      :items-per-page="pageSize"
      :per-page-options="perPageOptions"
      current-page-info="WHATSAPP_TEMPLATE_MGMT.TABLE.COUNT"
      class="!px-0"
      @update:current-page="emit('update:page', $event)"
      @update:items-per-page="emit('update:pageSize', $event)"
    />
  </div>
</template>
