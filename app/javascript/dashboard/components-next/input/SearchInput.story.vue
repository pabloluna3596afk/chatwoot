<script setup>
import { ref } from 'vue';
import SearchInput from './SearchInput.vue';

const query = ref('');
const clearableQuery = ref('ChatHub');
</script>

<template>
  <Story
    title="Components/SearchInput"
    :layout="{ type: 'grid', width: '400' }"
  >
    <Variant title="Sizes">
      <div class="flex flex-col gap-4 p-4 bg-n-background">
        <SearchInput v-model="query" placeholder="Search" size="sm" />
        <SearchInput v-model="query" placeholder="Search" size="md" />
      </div>
    </Variant>
    <Variant title="Clearable">
      <div class="p-4 bg-n-background">
        <SearchInput v-model="clearableQuery" placeholder="Search" clearable />
      </div>
    </Variant>
    <Variant title="RTL">
      <div dir="rtl" class="p-4 bg-n-background">
        <SearchInput v-model="query" placeholder="Search" clearable />
      </div>
    </Variant>
    <Variant title="Disabled">
      <div class="p-4 bg-n-background">
        <SearchInput
          v-model="clearableQuery"
          placeholder="Search"
          clearable
          disabled
        />
      </div>
    </Variant>
  </Story>
</template>
