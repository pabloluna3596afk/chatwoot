<script setup>
import BaseTable from 'dashboard/components-next/table/BaseTable.vue';
import BaseTableRow from 'dashboard/components-next/table/BaseTableRow.vue';
import BaseTableCell from 'dashboard/components-next/table/BaseTableCell.vue';
import ChannelIcon from 'dashboard/components-next/icon/ChannelIcon.vue';
import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';

defineProps({
  cardsOnMobile: { type: Boolean, default: false },
  columns: { type: Array, required: true },
  items: { type: Array, required: true },
  total: { type: Number, required: true },
  page: { type: Number, required: true },
  pageSize: { type: Number, required: true },
  perPageOptions: { type: Array, default: () => [] },
});
const emit = defineEmits(['update:page', 'update:pageSize', 'open']);
const columnClasses = key => {
  const widths = {
    NAME: 'w-[13rem] min-w-[13rem] max-w-[13rem]',
    CATEGORY:
      'hidden 2xl:table-cell 2xl:w-[7rem] 2xl:min-w-[7rem] 2xl:max-w-[7rem]',
    INBOX: 'hidden xl:table-cell xl:w-[7rem] xl:min-w-[7rem] xl:max-w-[7rem]',
    LANGUAGE:
      'hidden 2xl:table-cell 2xl:w-[5.5rem] 2xl:min-w-[5.5rem] 2xl:max-w-[5.5rem]',
    TYPE: 'hidden 2xl:table-cell 2xl:w-[5rem] 2xl:min-w-[5rem] 2xl:max-w-[5rem]',
    STATUS: 'w-[7rem] min-w-[7rem] max-w-[7rem]',
    META_STATUS: 'w-[9rem] min-w-[9rem] max-w-[9rem]',
    UPDATED:
      'hidden 2xl:table-cell 2xl:w-[8rem] 2xl:min-w-[8rem] 2xl:max-w-[8rem]',
    ACTIONS:
      'sticky right-0 z-10 w-[8rem] min-w-[8rem] max-w-[8rem] bg-n-solid-1 shadow-[-0.5rem_0_0.5rem_-0.5rem_rgba(0,0,0,0.2)]',
  };
  return widths[key] || '';
};
</script>

<template>
  <div>
    <BaseTable
      :class="{ 'hidden md:block': cardsOnMobile }"
      :headers="['', ...columns.map(column => column.label)]"
      :items="items"
      fixed
      :header-classes="[
        'w-12 min-w-12',
        ...columns.map(column => columnClasses(column.key)),
      ]"
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
          <BaseTableCell class="w-12 min-w-12">
            <span
              class="grid size-8 place-items-center rounded-lg border border-n-strong bg-n-alpha-2"
            >
              <ChannelIcon
                :inbox="{ channel_type: 'Channel::Whatsapp' }"
                class="size-5"
              />
            </span>
          </BaseTableCell>
          <BaseTableCell
            v-for="column in columns"
            :key="column.key"
            :class="columnClasses(column.key)"
          >
            <slot :name="column.key" :item="item">
              {{ item[column.key] }}
            </slot>
          </BaseTableCell>
        </BaseTableRow>
      </template>
    </BaseTable>
    <div
      v-if="cardsOnMobile"
      class="grid gap-3 md:hidden"
      data-testid="template-cards"
    >
      <article
        v-for="item in items"
        :key="item.key || item.id"
        class="grid min-w-0 gap-3 p-4 border rounded-xl border-n-weak bg-n-solid-1"
        tabindex="0"
        @click="emit('open', item)"
        @keydown.enter.self="emit('open', item)"
      >
        <dl class="grid min-w-0 gap-3">
          <div
            v-for="column in columns"
            :key="column.key"
            class="min-w-0 break-words"
          >
            <dt class="text-xs text-n-slate-11">{{ column.label }}</dt>
            <dd class="mt-1 text-sm text-n-slate-12">
              <slot :name="column.key" :item="item">
                {{ item[column.key] }}
              </slot>
            </dd>
          </div>
        </dl>
      </article>
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
