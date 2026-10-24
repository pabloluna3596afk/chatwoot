<script setup>
import ListCard from './ListCard.vue';
import InfoChip from './InfoChip.vue';
import Avatar from '../avatar/Avatar.vue';

const agents = [
  {
    name: 'Ana García',
    role: 'Administrator',
    tone: 'success',
    status: 'Verified',
  },
  {
    name: 'Luis Fernando Rodríguez',
    role: 'Agent',
    tone: 'success',
    status: 'Verified',
  },
  {
    name: 'María López',
    role: 'Agent',
    tone: 'warning',
    status: 'Verification pending',
  },
  {
    name: 'Carlos',
    role: 'Administrator',
    tone: 'success',
    status: 'Verified',
  },
];
const menuItems = [
  { action: 'edit', label: 'Edit', icon: 'i-lucide-pencil' },
  { action: 'delete', label: 'Delete', icon: 'i-lucide-trash' },
];
</script>

<template>
  <Story title="Components/ListCard" :layout="{ type: 'single', iframe: true }">
    <Variant title="Responsive list">
      <div class="flex flex-col gap-3 p-4 bg-n-background">
        <ListCard
          v-for="agent in agents"
          :key="agent.name"
          :title="agent.name"
          :subtitle="`${agent.name}@demo-empresa.co`"
          :menu-items="menuItems"
        >
          <template #avatar><Avatar :name="agent.name" :size="40" /></template>
          <template #chips>
            <InfoChip>{{ agent.role }}</InfoChip>
            <InfoChip :tone="agent.tone">{{ agent.status }}</InfoChip>
          </template>
        </ListCard>
      </div>
    </Variant>
    <Variant title="Chip tones">
      <div class="flex flex-wrap gap-2 p-4">
        <InfoChip
          v-for="tone in ['neutral', 'success', 'warning', 'error']"
          :key="tone"
          :tone="tone"
        >
          {{ tone }}
        </InfoChip>
      </div>
    </Variant>
  </Story>
</template>
