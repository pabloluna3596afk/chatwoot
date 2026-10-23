<script setup>
import { nextTick, ref } from 'vue';
import { useMapGetter } from 'dashboard/composables/store';
import { useAdmin } from 'dashboard/composables/useAdmin';
import { useConversationLabels } from 'dashboard/composables/useConversationLabels';
import { useKeyboardEvents } from 'dashboard/composables/useKeyboardEvents';
import Spinner from 'shared/components/Spinner.vue';
import LabelDropdown from 'shared/components/ui/label/LabelDropdown.vue';
import AddLabel from 'shared/components/ui/dropdown/AddLabel.vue';
import AddLabelModal from 'dashboard/routes/dashboard/settings/labels/AddLabel.vue';
import { useLabelNavigation } from 'dashboard/composables/useLabelNavigation';

const { isAdmin } = useAdmin();
const {
  savedLabels,
  activeLabels,
  accountLabels,
  addLabelToConversation,
  removeLabelFromConversation,
} = useConversationLabels();
const conversationUiFlags = useMapGetter('conversationLabels/getUIFlags');
const { goToLabel } = useLabelNavigation();
const showSearchDropdownLabel = ref(false);
const createModalVisible = ref(false);
const prefillTitle = ref('');
const labelTrigger = ref(null);
const toggleLabels = () => {
  showSearchDropdownLabel.value = !showSearchDropdownLabel.value;
};
const closeDropdownLabel = () => {
  showSearchDropdownLabel.value = false;
};
const createLabel = title => {
  prefillTitle.value = title;
  closeDropdownLabel();
  createModalVisible.value = true;
};
const hideCreateModal = async () => {
  createModalVisible.value = false;
  await nextTick();
  labelTrigger.value?.querySelector('button')?.focus();
};
useKeyboardEvents({
  KeyL: {
    action: event => {
      if (createModalVisible.value) return;
      event.preventDefault();
      toggleLabels();
    },
  },
  Escape: { action: closeDropdownLabel, allowOnFocusedInput: true },
});
</script>

<template>
  <div class="sidebar-labels-wrap">
    <div v-if="!conversationUiFlags.isFetching" class="w-full">
      <div
        ref="labelTrigger"
        v-on-clickaway="closeDropdownLabel"
        class="relative flex flex-wrap leading-6"
        @keyup.esc="closeDropdownLabel"
      >
        <AddLabel @add="toggleLabels" />
        <woot-label
          v-for="label in activeLabels"
          :key="label.id"
          :title="label.title"
          :description="label.description"
          show-close
          :color="label.color"
          variant="smooth"
          class="max-w-[calc(100%-0.5rem)]"
          selectable
          @remove="removeLabelFromConversation"
          @select="goToLabel(label.title)"
        />

        <div
          :class="{
            'block visible': showSearchDropdownLabel,
            'hidden invisible': !showSearchDropdownLabel,
          }"
          class="border rounded-lg bg-n-alpha-3 top-6 backdrop-blur-[100px] absolute w-full shadow-lg border-n-strong dark:border-n-strong p-2 box-border z-[9999]"
        >
          <LabelDropdown
            v-if="showSearchDropdownLabel"
            :account-labels="accountLabels"
            :selected-labels="savedLabels"
            :allow-creation="isAdmin"
            @create="createLabel"
            @add="addLabelToConversation"
            @remove="removeLabelFromConversation"
          />
        </div>
      </div>
    </div>
    <Spinner v-else />
    <Teleport to="body">
      <woot-modal
        v-if="createModalVisible"
        v-model:show="createModalVisible"
        @close="hideCreateModal"
      >
        <AddLabelModal
          :prefill-title="prefillTitle"
          @created="addLabelToConversation"
          @close="hideCreateModal"
        />
      </woot-modal>
    </Teleport>
  </div>
</template>
