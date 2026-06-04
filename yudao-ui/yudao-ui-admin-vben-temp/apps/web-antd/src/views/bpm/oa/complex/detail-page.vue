<script lang="ts" setup>
import type { ComplexFieldConfig, ComplexOAModuleKey } from './config';

import { computed, onMounted, ref } from 'vue';
import { useRoute } from 'vue-router';

import { ContentWrap } from '@vben/common-ui';
import { formatDateTime } from '@vben/utils';

import { Descriptions, Space, Spin, Tag } from 'ant-design-vue';

import { getDictOptions } from '@vben/hooks';
import { DICT_TYPE } from '@vben/constants';

import { getComplexModuleViewConfig, parseJsonArray } from './config';

defineOptions({ name: 'OAComplexDetailPage' });

const props = defineProps<{
  id?: string;
  moduleKey: ComplexOAModuleKey;
}>();

const route = useRoute();
const config = getComplexModuleViewConfig(props.moduleKey);
const loading = ref(false);
const detailData = ref<Record<string, any>>({});

const queryId = computed(() => Number(props.id || route.query.id));

const statusDict = computed(() => getDictOptions(DICT_TYPE.BPM_PROCESS_INSTANCE_STATUS, 'number'));

function getStatusText(status?: number) {
  const matched = statusDict.value.find((item) => item.value === status);
  return matched?.label || '-';
}

function getStatusColor(status?: number) {
  switch (status) {
    case 1:
      return 'processing';
    case 2:
      return 'success';
    case 3:
      return 'error';
    case 4:
      return 'default';
    default:
      return 'default';
  }
}

function getSelectLabel(field: ComplexFieldConfig, value: unknown) {
  const matched = field.options?.find((item) => String(item.value) === String(value));
  return matched?.label || value || '-';
}

function renderValue(field: ComplexFieldConfig) {
  const value = detailData.value[field.field];
  if (field.type === 'datetime') {
    return value ? formatDateTime(value) : '-';
  }
  if (field.type === 'select') {
    return getSelectLabel(field, value);
  }
  if (field.type === 'switch') {
    return value ? '是' : '否';
  }
  if (field.type === 'files') {
    const files = parseJsonArray(value);
    return files.length > 0 ? files : [];
  }
  return value || '-';
}

async function loadDetail() {
  loading.value = true;
  try {
    detailData.value = await config.getDetailRequest(queryId.value);
  } finally {
    loading.value = false;
  }
}

onMounted(() => {
  loadDetail();
});
</script>

<template>
  <ContentWrap class="m-2">
    <Spin :spinning="loading" tip="加载中...">
      <Descriptions :column="1" bordered>
        <Descriptions.Item label="审批状态">
          <Tag :color="getStatusColor(detailData.status)">
            {{ getStatusText(detailData.status) }}
          </Tag>
        </Descriptions.Item>
        <Descriptions.Item
          v-for="field in config.detailFields"
          :key="field.field"
          :label="field.label"
        >
          <template v-if="field.type === 'files'">
            <Space direction="vertical">
              <a
                v-for="file in renderValue(field)"
                :key="file"
                :href="file"
                target="_blank"
              >
                {{ file }}
              </a>
            </Space>
          </template>
          <template v-else>
            {{ renderValue(field) }}
          </template>
        </Descriptions.Item>
      </Descriptions>
    </Spin>
  </ContentWrap>
</template>
