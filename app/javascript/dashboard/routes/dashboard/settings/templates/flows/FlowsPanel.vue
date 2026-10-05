<script setup>
// The "Formularios" tab of the templates page: the forms of the account, a new one (start screen) and the builder.
import { computed, onMounted, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useAlert } from 'dashboard/composables';
import { usePolicy } from 'dashboard/composables/usePolicy';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import FlowEditor from './FlowEditor.vue';
import FlowStart from './FlowStart.vue';

const { t } = useI18n();
const { checkPermissions } = usePolicy();

const isAdmin = computed(() => checkPermissions(['administrator']));

// list | start | edit
const view = ref('list');
const flows = ref([]);
const isLoading = ref(false);
const editing = ref(null);
const toDelete = ref(null);
const deleteDialogRef = ref(null);
const isDeleting = ref(false);

const load = async () => {
  isLoading.value = true;
  try {
    const { data } = await WhatsappFlowsAPI.list();
    flows.value = data.payload || [];
  } catch {
    useAlert(t('WHATSAPP_FLOWS.LIST.LOAD_ERROR'));
  } finally {
    isLoading.value = false;
  }
};

onMounted(load);

const startNew = () => {
  view.value = 'start';
};

const created = flow => {
  editing.value = flow;
  view.value = 'edit';
};

const edit = async summary => {
  try {
    const { data } = await WhatsappFlowsAPI.show(summary.id);
    editing.value = data;
    view.value = 'edit';
  } catch {
    useAlert(t('WHATSAPP_FLOWS.LIST.LOAD_ERROR'));
  }
};

const backToList = () => {
  view.value = 'list';
  editing.value = null;
  load();
};

const askDelete = flow => {
  toDelete.value = flow;
  deleteDialogRef.value?.open();
};

const confirmDelete = async () => {
  isDeleting.value = true;
  try {
    await WhatsappFlowsAPI.remove(toDelete.value.id);
    deleteDialogRef.value?.close();
    useAlert(t('WHATSAPP_FLOWS.LIST.DELETED'));
    await load();
  } catch {
    useAlert(t('WHATSAPP_FLOWS.LIST.DELETE_ERROR'));
  } finally {
    isDeleting.value = false;
  }
};

const dateOf = seconds => new Date(seconds * 1000).toLocaleDateString();
</script>

<template>
  <div data-testid="flows-panel">
    <FlowStart
      v-if="view === 'start'"
      @create="created"
      @cancel="view = 'list'"
    />
    <FlowEditor
      v-else-if="view === 'edit' && editing"
      :flow="editing"
      @back="backToList"
      @saved="editing = { ...editing, ...$event }"
    />

    <div v-else class="flex flex-col gap-4">
      <div class="flex flex-wrap items-center justify-between gap-3">
        <div>
          <h2 class="text-heading-2 text-n-slate-12">
            {{ $t('WHATSAPP_FLOWS.LIST.TITLE') }}
          </h2>
          <p class="mt-1 text-body-main text-n-slate-11">
            {{ $t('WHATSAPP_FLOWS.LIST.DESCRIPTION') }}
          </p>
        </div>
        <Button
          v-if="isAdmin"
          type="button"
          icon="i-lucide-plus"
          size="sm"
          :label="$t('WHATSAPP_FLOWS.LIST.NEW')"
          data-testid="flow-new"
          @click="startNew"
        />
      </div>

      <p
        v-if="!isLoading && !flows.length"
        class="py-8 text-center text-n-slate-11"
        data-testid="flows-empty"
      >
        {{ $t('WHATSAPP_FLOWS.LIST.EMPTY') }}
      </p>

      <div v-else class="border-t divide-y divide-n-weak border-n-weak">
        <div
          v-for="flow in flows"
          :key="flow.id"
          class="flex items-center justify-between gap-4 py-4"
          data-testid="flow-row"
        >
          <div class="flex flex-col min-w-0 gap-1">
            <span class="truncate text-heading-3 text-n-slate-12">
              {{ flow.name }}
            </span>
            <span
              class="flex flex-wrap items-center gap-2 text-body-main text-n-slate-11"
            >
              <span>
                {{ $t('WHATSAPP_FLOWS.LIST.SCREENS', { n: flow.screens }) }}
              </span>
              <span
                v-for="category in flow.categories"
                :key="category"
                class="px-2 py-0.5 text-xs rounded-md bg-n-alpha-2"
              >
                {{ $t(`WHATSAPP_FLOWS.CATEGORIES.${category}`) }}
              </span>
              <span>{{ dateOf(flow.updated_at) }}</span>
            </span>
          </div>
          <div v-if="isAdmin" class="flex items-center gap-1 shrink-0">
            <Button
              type="button"
              color="slate"
              size="sm"
              icon="i-lucide-pencil"
              :aria-label="$t('WHATSAPP_FLOWS.LIST.EDIT')"
              data-testid="flow-edit"
              @click="edit(flow)"
            />
            <Button
              type="button"
              color="ruby"
              size="sm"
              icon="i-lucide-trash-2"
              :aria-label="$t('WHATSAPP_FLOWS.LIST.DELETE')"
              data-testid="flow-delete"
              @click="askDelete(flow)"
            />
          </div>
        </div>
      </div>
    </div>

    <Dialog
      v-if="isAdmin"
      ref="deleteDialogRef"
      type="alert"
      :title="$t('WHATSAPP_FLOWS.LIST.DELETE_TITLE')"
      :confirm-button-label="$t('WHATSAPP_FLOWS.LIST.DELETE')"
      :is-loading="isDeleting"
      @confirm="confirmDelete"
    >
      <p v-if="toDelete" class="text-sm text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.LIST.DELETE_BODY', { name: toDelete.name }) }}
      </p>
    </Dialog>
  </div>
</template>
