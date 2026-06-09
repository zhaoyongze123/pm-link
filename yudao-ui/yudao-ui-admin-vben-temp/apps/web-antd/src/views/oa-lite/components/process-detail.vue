<script lang="ts" setup>
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';
import type { SystemUserApi } from '#/api/system/user';
import type { OAModuleApiKey } from '#/views/bpm/oa/shared/config';

import { computed, h, nextTick, ref, shallowRef, watch } from 'vue';

import { prompt } from '@vben/common-ui';
import {
  BpmFieldPermissionType,
  BpmModelFormType,
  BpmModelType,
  BpmProcessInstanceStatus,
} from '@vben/constants';
import { formatDateTime } from '@vben/utils';
import { useI18n } from '@vben/locales';

import { Button, Empty, message, Spin, Tag, Textarea } from 'ant-design-vue';

import {
  cancelProcessInstanceByStartUser,
  getApprovalDetail,
  getProcessInstanceBpmnModelView,
} from '#/api/bpm/processInstance';
import { withdrawTask } from '#/api/bpm/task';
import { getSimpleUserList } from '#/api/system/user';
import { setConfAndFields2 } from '#/components/form-create';
import { registerComponent } from '#/utils';
import ProcessInstanceBpmnViewer from '#/views/bpm/processInstance/detail/modules/bpm-viewer.vue';
import ProcessInstanceOperationButton from '#/views/bpm/processInstance/detail/modules/operation-button.vue';
import ProcessInstanceSimpleViewer from '#/views/bpm/processInstance/detail/modules/simple-bpm-viewer.vue';
import BpmProcessInstanceTaskList from '#/views/bpm/processInstance/detail/modules/task-list.vue';
import ProcessInstanceTimeline from '#/views/bpm/processInstance/detail/modules/time-line.vue';

defineOptions({ name: 'OaLiteProcessDetail' });

export type OaLiteDetailSection =
  | 'copied'
  | 'initiated'
  | 'pending'
  | 'processed';

export interface OaLiteDetailRequest {
  activityId?: string;
  businessKey?: string;
  processInstanceId: string;
  taskId?: string;
}

const props = defineProps<{
  request: null | OaLiteDetailRequest;
  section: OaLiteDetailSection;
}>();

const emit = defineEmits<{
  recreate: [
    processInstanceId: string,
    businessKey?: string,
    processDefinitionKey?: string,
    formCustomCreatePath?: string,
  ];
  refresh: [];
}>();
const { t } = useI18n();

const loading = ref(false);
const activeTab = ref<'diagram' | 'form' | 'record'>('form');
const approvalDetail = ref<BpmProcessInstanceApi.ApprovalDetailRespVO | null>(
  null,
);
const processModelView = ref<any>({});
const operationButtonRef = ref();
const taskListRef = ref();
const userOptions = ref<SystemUserApi.User[]>([]);
const businessFormComponent = shallowRef<any>(null);
const normalFormApi = ref<any>();
const normalForm = ref({
  option: {},
  rule: [],
  value: {},
});
const writableFields: string[] = [];

const processInstance = computed(() => approvalDetail.value?.processInstance);
const processDefinition = computed(
  () => approvalDetail.value?.processDefinition || null,
);
const businessModuleKey = computed<OAModuleApiKey | undefined>(() => {
  const key = processDefinition.value?.key || '';
  if (key.startsWith('oa_')) {
    return key.slice(3) as OAModuleApiKey;
  }
  return undefined;
});
const activityNodes = computed(() => approvalDetail.value?.activityNodes || []);
const todoTask = computed(() => approvalDetail.value?.todoTask);

const canCancelProcess = computed(
  () =>
    props.section === 'initiated' &&
    processInstance.value?.status === BpmProcessInstanceStatus.RUNNING,
);
const canRecreateProcess = computed(
  () =>
    props.section === 'initiated' &&
    processInstance.value?.status !== BpmProcessInstanceStatus.RUNNING &&
    Boolean(processInstance.value?.businessKey),
);
const canWithdrawTask = computed(
  () => props.section === 'processed' && Boolean(props.request?.taskId),
);
const showReadonlyChip = computed(() => props.section === 'copied');
const showOperationButton = computed(
  () => props.section === 'pending' && Boolean(todoTask.value?.id),
);

function getStatusText(status?: number) {
  switch (status) {
    case BpmProcessInstanceStatus.APPROVE: {
      return t('page.oaLite.status.approved');
    }
    case BpmProcessInstanceStatus.CANCEL: {
      return t('page.oaLite.status.cancelled');
    }
    case BpmProcessInstanceStatus.REJECT: {
      return t('page.oaLite.status.rejected');
    }
    case BpmProcessInstanceStatus.RUNNING: {
      return t('page.oaLite.status.running');
    }
    default: {
      return t('page.oaLite.status.processing');
    }
  }
}

function getStatusTone(status?: number) {
  if (status === BpmProcessInstanceStatus.APPROVE) {
    return 'success';
  }
  if (status === BpmProcessInstanceStatus.REJECT) {
    return 'danger';
  }
  if (status === BpmProcessInstanceStatus.CANCEL) {
    return 'muted';
  }
  if (status === BpmProcessInstanceStatus.RUNNING) {
    return 'primary';
  }
  return 'neutral';
}

function resetNormalForm() {
  normalForm.value = {
    option: {},
    rule: [],
    value: {},
  };
  businessFormComponent.value = null;
  processModelView.value = {};
  approvalDetail.value = null;
  writableFields.splice(0);
}

function setFieldPermission(field: string, permission: string) {
  if (permission === BpmFieldPermissionType.READ) {
    normalFormApi.value?.disabled(true, field);
  }
  if (permission === BpmFieldPermissionType.WRITE) {
    normalFormApi.value?.disabled(false, field);
    writableFields.push(field);
  }
  if (permission === BpmFieldPermissionType.NONE) {
    normalFormApi.value?.hidden(true, field);
  }
}

async function ensureUserOptions() {
  if (userOptions.value.length > 0) {
    return;
  }
  userOptions.value = await getSimpleUserList();
}

async function loadDetail() {
  if (!props.request) {
    resetNormalForm();
    return;
  }
  loading.value = true;
  try {
    const data = await getApprovalDetail({
      activityId: props.request.activityId,
      processInstanceId: props.request.processInstanceId,
      taskId: props.request.taskId,
    });
    approvalDetail.value = data;

    if (!data?.processDefinition || !data?.processInstance) {
      return;
    }

    const processDefinitionData = data.processDefinition;
    if (processDefinitionData.formType === BpmModelFormType.NORMAL) {
      writableFields.splice(0);
      if (processDefinitionData.formConf && processDefinitionData.formFields) {
        setConfAndFields2(
          normalForm,
          processDefinitionData.formConf,
          processDefinitionData.formFields || [],
          data.processInstance.formVariables,
        );
      } else {
        normalForm.value = {
          option: {},
          rule: [],
          value: data.processInstance.formVariables || {},
        };
      }
      await nextTick();
      normalFormApi.value?.btn?.show(false);
      normalFormApi.value?.resetBtn?.show(false);
      normalFormApi.value?.disabled(true);
      Object.entries(data.formFieldsPermission || {}).forEach(
        ([field, permission]) => {
          setFieldPermission(field, permission as string);
        },
      );
    } else {
      const componentPath = processDefinitionData.formCustomViewPath || '';
      businessFormComponent.value =
        registerComponent(componentPath) ||
        (componentPath.includes('/bpm/oa/')
          ? registerComponent('/bpm/oa/shared/detail-page')
          : null);
    }

    processModelView.value = await getProcessInstanceBpmnModelView(
      props.request.processInstanceId,
    );

    await ensureUserOptions();
    await nextTick();
    operationButtonRef.value?.loadTodoTask(data.todoTask);
  } finally {
    loading.value = false;
  }
}

async function handleWithdraw() {
  if (!props.request?.taskId) {
    return;
  }
  await withdrawTask(props.request.taskId);
  message.success(t('page.oaLite.messages.withdrawSuccess'));
  emit('refresh');
}

function handleCancelProcess() {
  if (!processInstance.value?.id) {
    return;
  }
  prompt({
    component: () =>
      h(Textarea, {
        allowClear: true,
        placeholder: t('page.oaLite.processDetail.cancelReasonPlaceholder'),
        rows: 2,
      }),
    content: t('page.oaLite.processDetail.cancelReasonPlaceholder'),
    modelPropName: 'value',
    title: t('page.oaLite.processDetail.cancelProcess'),
  }).then(async (reason) => {
    if (!reason) {
      return;
    }
    await cancelProcessInstanceByStartUser(processInstance.value!.id, reason);
    message.success(t('page.oaLite.messages.cancelSuccess'));
    emit('refresh');
  });
}

function handleRecreate() {
  if (!props.request?.processInstanceId) {
    return;
  }
  emit(
    'recreate',
    props.request.processInstanceId,
    processInstance.value?.businessKey,
    processDefinition.value?.key,
    processDefinition.value?.formCustomCreatePath || undefined,
  );
}

function handleRefresh() {
  emit('refresh');
}

watch(
  () => props.request,
  async () => {
    activeTab.value = 'form';
    await loadDetail();
  },
  { deep: true, immediate: true },
);

watch(
  () => activeTab.value,
  async (tab) => {
    if (tab !== 'record') {
      return;
    }
    await nextTick();
    taskListRef.value?.refresh();
  },
);
</script>

<template>
  <div class="oa-lite-process-detail">
    <Spin :spinning="loading">
      <template v-if="processInstance && processDefinition">
        <div class="oa-lite-process-head">
          <div class="oa-lite-process-head-main">
            <div class="oa-lite-process-name-row">
              <h3 class="oa-lite-process-name">{{ processInstance.name }}</h3>
              <span
                class="oa-lite-status-chip"
                :class="`tone-${getStatusTone(processInstance.status)}`"
              >
                {{ getStatusText(processInstance.status) }}
              </span>
            </div>
            <div class="oa-lite-process-desc-row">
              <span>
                {{ t('page.oaLite.processDetail.startUser') }}：{{ processInstance.startUser?.nickname || '-' }}
              </span>
              <span>
                {{ t('page.oaLite.processDetail.submitTime') }}：{{ formatDateTime(processInstance.startTime || processInstance.createTime) }}
              </span>
            </div>
            <div class="oa-lite-process-id">
              {{ t('page.oaLite.processDetail.processNo') }}：{{ processInstance.id || '-' }}
              <span class="oa-lite-process-id-divider">|</span>
              {{ t('page.oaLite.processDetail.businessKey') }}：{{ processInstance.businessKey || '-' }}
            </div>
          </div>

          <div class="oa-lite-detail-actions">
            <Button
              v-if="canWithdrawTask"
              class="oa-lite-white-button"
              @click="handleWithdraw"
            >
              {{ t('page.oaLite.processDetail.withdrawTask') }}
            </Button>
            <Button
              v-if="canCancelProcess"
              class="oa-lite-white-button"
              @click="handleCancelProcess"
            >
              {{ t('page.oaLite.processDetail.cancelProcess') }}
            </Button>
            <Button
              v-if="canRecreateProcess"
              type="primary"
              class="oa-lite-white-primary"
              @click="handleRecreate"
            >
              {{ t('page.oaLite.processDetail.restartProcess') }}
            </Button>
            <Tag v-if="showReadonlyChip" class="oa-lite-readonly-tag">
              {{ t('page.oaLite.processDetail.readonly') }}
            </Tag>
          </div>
        </div>

        <div class="oa-lite-process-tabs">
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'form' }"
            @click="activeTab = 'form'"
          >
            {{ t('page.oaLite.processDetail.tabs.detail') }}
          </button>
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'diagram' }"
            @click="activeTab = 'diagram'"
          >
            {{ t('page.oaLite.processDetail.tabs.diagram') }}
          </button>
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'record' }"
            @click="activeTab = 'record'"
          >
            {{ t('page.oaLite.processDetail.tabs.record') }}
          </button>
        </div>

        <div v-if="activeTab === 'form'" class="oa-lite-detail-grid">
          <section class="oa-lite-detail-card oa-lite-detail-card-form">
            <div class="oa-lite-detail-card-title">{{ t('page.oaLite.processDetail.businessForm') }}</div>
            <component
              :is="businessFormComponent"
              v-if="
                processDefinition.formType === BpmModelFormType.CUSTOM &&
                businessFormComponent
              "
              :id="String(processInstance.businessKey || '')"
              :module-key="businessModuleKey"
              class="oa-lite-business-form"
            />
            <form-create
              v-else-if="processDefinition.formType === BpmModelFormType.NORMAL"
              v-model="normalForm.value"
              v-model:api="normalFormApi"
              :option="normalForm.option"
              :rule="normalForm.rule"
            />
            <Empty v-else :description="t('page.oaLite.processDetail.emptyBusinessForm')" />
          </section>

          <aside class="oa-lite-detail-card">
            <div class="oa-lite-detail-card-title">{{ t('page.oaLite.processDetail.timeline') }}</div>
            <ProcessInstanceTimeline :activity-nodes="activityNodes" />
          </aside>
        </div>

        <div v-else-if="activeTab === 'diagram'" class="oa-lite-detail-card">
          <div class="oa-lite-detail-card-title">{{ t('page.oaLite.processDetail.tabs.diagram') }}</div>
          <ProcessInstanceSimpleViewer
            v-if="processDefinition.modelType === BpmModelType.SIMPLE"
            :loading="loading"
            :model-view="processModelView"
          />
          <ProcessInstanceBpmnViewer
            v-else
            :loading="loading"
            :model-view="processModelView"
          />
        </div>

        <div v-else class="oa-lite-detail-card">
          <div class="oa-lite-detail-card-title">{{ t('page.oaLite.processDetail.tabs.record') }}</div>
          <BpmProcessInstanceTaskList
            ref="taskListRef"
            :id="String(processInstance.id)"
            :loading="loading"
          />
        </div>

        <div
          v-if="showOperationButton"
          class="oa-lite-detail-card oa-lite-operation-card"
        >
          <div class="oa-lite-detail-card-title">{{ t('page.oaLite.processDetail.approvalAction') }}</div>
          <div class="oa-lite-operation-bar">
            <ProcessInstanceOperationButton
              ref="operationButtonRef"
              :normal-form="normalForm"
              :normal-form-api="normalFormApi"
              :process-definition="processDefinition"
              :process-instance="processInstance"
              :user-options="userOptions"
              :writable-fields="writableFields"
              @success="handleRefresh"
            />
          </div>
        </div>
      </template>

      <div v-else class="oa-lite-detail-empty">
        <Empty :description="t('page.oaLite.processDetail.emptySelect')" />
      </div>
    </Spin>
  </div>
</template>

<style lang="scss" scoped>
.oa-lite-process-detail {
  display: flex;
  flex-direction: column;
  gap: 18px;
  min-height: 100%;
}

.oa-lite-process-detail :deep(.ant-spin-nested-loading),
.oa-lite-process-detail :deep(.ant-spin-container) {
  height: 100%;
}

.oa-lite-process-detail :deep(.ant-spin-container) {
  display: flex;
  flex-direction: column;
  gap: 18px;
}

.oa-lite-process-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 20px;
}

.oa-lite-process-head-main {
  min-width: 0;
}

.oa-lite-process-name-row {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
}

.oa-lite-process-name {
  margin: 0;
  font-size: 22px;
  font-weight: 600;
  color: var(--oa-ink);
}

.oa-lite-process-desc-row {
  margin-top: 10px;
  display: flex;
  flex-wrap: wrap;
  gap: 10px 18px;
  font-size: 13px;
  color: var(--oa-ink-soft);
}

.oa-lite-process-id {
  margin-top: 10px;
  font-size: 12px;
  color: var(--oa-ink-faint);
}

.oa-lite-process-id-divider {
  margin: 0 8px;
}

.oa-lite-detail-actions {
  display: flex;
  align-items: center;
  gap: 12px;
  flex-wrap: wrap;
  justify-content: flex-end;
}

.oa-lite-process-tabs {
  display: flex;
  gap: 18px;
  border-bottom: 1px solid var(--oa-shell-border);
  padding-bottom: 12px;
}

.oa-lite-process-tab {
  border: none;
  background: transparent;
  color: var(--oa-ink-soft);
  border-radius: 0;
  padding: 8px 2px 10px;
  cursor: pointer;
  transition: color 0.18s ease;
}

.oa-lite-process-tab.active {
  color: var(--oa-accent);
  box-shadow: inset 0 -1px 0 var(--oa-accent);
}

.oa-lite-detail-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(280px, 0.8fr);
  gap: 24px;
}

.oa-lite-detail-card {
  background: transparent;
  border-radius: 0;
  border: 0;
  border-top: 1px solid var(--oa-shell-border);
  padding: 18px 0 0;
  min-width: 0;
}

.oa-lite-detail-card-form {
  overflow: hidden;
}

.oa-lite-detail-card-title {
  font-size: 15px;
  font-weight: 600;
  color: var(--oa-ink);
  margin-bottom: 14px;
}

.oa-lite-detail-empty {
  min-height: 320px;
  border-radius: 0;
  border-top: 1px dashed var(--oa-shell-border);
  border-bottom: 1px dashed var(--oa-shell-border);
  background: transparent;
  display: flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-operation-card {
  margin-top: 4px;
  padding-top: 20px;
  border-top-color: color-mix(
    in srgb,
    var(--oa-shell-border-strong, var(--oa-shell-border)) 88%,
    transparent
  );
}

.oa-lite-operation-bar {
  position: relative;

  &::before {
    content: '';
    position: absolute;
    inset: -2px 0 auto;
    height: 1px;
    background: color-mix(in srgb, var(--oa-shell-border) 64%, transparent);
    opacity: 0.9;
    pointer-events: none;
  }

  :deep(.ant-btn) {
    border-radius: 0;
  }

  :deep(.oa-process-actions) {
    padding-top: 0;
    border-top: 0;
  }
}

.oa-lite-status-chip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 24px;
  border-radius: 0;
  padding: 0 2px 2px;
  font-size: 12px;
  font-weight: 600;
  border-bottom: 1px solid var(--oa-shell-border);
}

.oa-lite-status-chip.tone-primary {
  background: transparent;
  border-bottom-color: color-mix(in srgb, var(--oa-accent) 36%, var(--oa-shell-border));
  color: var(--oa-accent);
}

.oa-lite-status-chip.tone-success {
  background: transparent;
  border-bottom-color: color-mix(in srgb, var(--oa-success) 42%, var(--oa-shell-border));
  color: var(--oa-success-text);
}

.oa-lite-status-chip.tone-danger {
  background: transparent;
  border-bottom-color: color-mix(in srgb, var(--oa-danger-text) 42%, var(--oa-shell-border));
  color: var(--oa-danger-text);
}

.oa-lite-status-chip.tone-muted,
.oa-lite-status-chip.tone-neutral {
  background: transparent;
  color: var(--oa-ink-soft);
}

.oa-lite-white-button,
.oa-lite-white-primary {
  border-radius: 0;
}

.oa-lite-readonly-tag {
  border-radius: 0;
  background: transparent;
  color: var(--oa-accent);
  border-color: color-mix(in srgb, var(--oa-accent) 34%, var(--oa-shell-border));
}

.oa-lite-business-form {
  :deep(.m-2) {
    margin: 0 !important;
  }

  :deep(.mx-4) {
    margin-left: 0 !important;
    margin-right: 0 !important;
  }
}

.oa-lite-process-detail {
  :deep(.oa-process-actions-eyebrow) {
    color: var(--oa-ink-faint);
  }

  :deep(.oa-process-actions-caption) {
    color: var(--oa-ink-soft);
  }

  :deep(.oa-process-actions-bar .ant-btn) {
    min-height: 40px;
    border-color: color-mix(in srgb, var(--oa-shell-border) 92%, transparent);
    background: color-mix(
      in srgb,
      var(--oa-shell-surface-muted) 78%,
      var(--oa-shell-surface) 22%
    );
    color: var(--oa-ink);
  }

  :deep(.oa-process-actions-bar .ant-btn:hover),
  :deep(.oa-process-actions-bar .ant-btn:focus-visible) {
    border-color: color-mix(in srgb, var(--oa-accent) 40%, var(--oa-shell-border));
    color: var(--oa-accent);
    background: color-mix(
      in srgb,
      var(--oa-accent-soft) 22%,
      var(--oa-shell-surface) 78%
    );
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-primary) {
    background: var(--oa-accent);
    border-color: var(--oa-accent);
    color: var(--oa-accent-contrast);
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-primary.ant-btn-dangerous) {
    background: color-mix(in srgb, var(--oa-danger-text) 90%, #b42318);
    border-color: color-mix(in srgb, var(--oa-danger-text) 88%, #b42318);
    color: #fff;
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-background-ghost) {
    background: transparent;
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-dashed) {
    border-style: solid;
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-primary.ant-btn-background-ghost) {
    border-color: color-mix(in srgb, var(--oa-accent) 54%, var(--oa-shell-border));
    color: var(--oa-accent);
    background: color-mix(
      in srgb,
      var(--oa-accent-soft) 18%,
      transparent
    );
  }

  :deep(.oa-process-actions-bar .ant-btn.ant-btn-primary.ant-btn-background-ghost.ant-btn-dangerous) {
    border-color: color-mix(
      in srgb,
      var(--oa-danger-text) 52%,
      var(--oa-shell-border)
    );
    color: var(--oa-danger-text);
    background: color-mix(in srgb, var(--oa-danger-text) 10%, transparent);
  }

  :deep(.oa-process-actions-bar .ant-btn[disabled]),
  :deep(.oa-process-actions-bar .ant-btn[disabled]:hover) {
    border-color: color-mix(in srgb, var(--oa-shell-border) 90%, transparent) !important;
    background: color-mix(
      in srgb,
      var(--oa-shell-surface-subtle) 88%,
      var(--oa-shell-surface) 12%
    ) !important;
    color: var(--oa-ink-soft) !important;
    opacity: 0.88;
  }

  :deep(.ant-timeline-item-content) {
    color: var(--oa-ink) !important;
  }

  :deep(.bg-card) {
    background: transparent !important;
    border-top: 1px solid var(--oa-shell-border);
    border-radius: 0;
  }

  :deep(.simple-process-model-container) {
    border-top: 1px solid var(--oa-shell-border);
    border-bottom: 1px solid var(--oa-shell-border);
    border-left: 0;
    border-right: 0;
    border-radius: 0;
    overflow: hidden;
  }

  :deep(.simple-process-model-container .ant-btn),
  :deep(.simple-process-model-container .ant-btn > span),
  :deep(.simple-process-model-container .ant-btn .iconify) {
    color: var(--oa-ink) !important;
  }

  :deep(.simple-process-model-container .ant-btn) {
    background: transparent !important;
    border-color: var(--oa-shell-border) !important;
    box-shadow: none !important;
  }

  :deep(.vxe-table--render-default),
  :deep(.vxe-table--render-default .vxe-table--header-wrapper),
  :deep(.vxe-table--render-default .vxe-table--body-wrapper),
  :deep(.vxe-table--render-default .vxe-body--column),
  :deep(.vxe-table--render-default .vxe-header--column) {
    background: var(--oa-shell-surface) !important;
  }

  :deep(.vxe-table--render-default .vxe-cell),
  :deep(.vxe-table--render-default .vxe-table--empty-content) {
    color: var(--oa-ink) !important;
  }

  :deep(.vxe-table--render-default .vxe-header--column .vxe-cell) {
    color: var(--oa-ink-soft) !important;
    font-weight: 600;
  }
}

:global(body.oa-lite-theme-dark) .oa-lite-process-detail {
  :deep(.oa-process-actions-eyebrow) {
    color: color-mix(in srgb, var(--oa-ink-soft) 78%, white 22%);
  }

  :deep(.oa-process-actions-title),
  :deep(.oa-process-actions-caption),
  :deep(.oa-process-inline-section-title),
  :deep(.ant-form-item-label > label),
  :deep(.ant-form-item-extra),
  :deep(.ant-form-item-explain),
  :deep(.ant-select-selection-item),
  :deep(.ant-select-selection-placeholder),
  :deep(.ant-select-arrow),
  :deep(.ant-input-prefix),
  :deep(.ant-input-show-count-suffix),
  :deep(.ant-popover-title),
  :deep(.ant-empty-description) {
    color: var(--oa-ink) !important;
  }

  :deep(.oa-process-inline-note) {
    color: color-mix(in srgb, var(--oa-ink-soft) 84%, white 16%);
    border-left-color: color-mix(
      in srgb,
      var(--oa-danger-text) 62%,
      var(--oa-shell-border)
    );
  }

  :deep(.oa-process-actions .ant-popover-arrow::before),
  :deep(.oa-process-actions .ant-popover-arrow::after) {
    background: var(--oa-shell-surface-raised);
  }

  :deep(.oa-process-actions .ant-popover-inner) {
    border-color: color-mix(
      in srgb,
      var(--oa-shell-border-strong, var(--oa-shell-border)) 88%,
      transparent
    );
    background: var(--oa-shell-surface-raised);
    box-shadow: 0 22px 50px rgb(1 8 20 / 48%);
  }

  :deep(.oa-process-actions .ant-popover-inner-content),
  :deep(.oa-process-action-panel) {
    background: var(--oa-shell-surface-raised);
  }

  :deep(.oa-process-action-panel) {
    color: var(--oa-ink);
  }

  :deep(.oa-process-inline-section) {
    border-bottom-color: color-mix(
      in srgb,
      var(--oa-shell-border-strong, var(--oa-shell-border)) 86%,
      transparent
    );
  }

  :deep(.oa-process-actions .ant-input),
  :deep(.oa-process-actions .ant-input-affix-wrapper),
  :deep(.oa-process-actions .ant-select-selector),
  :deep(.oa-process-actions .ant-image),
  :deep(.oa-process-actions .ant-btn:not(.ant-btn-primary):not(.ant-btn-dangerous)) {
    border-color: color-mix(
      in srgb,
      var(--oa-shell-border-strong, var(--oa-shell-border)) 92%,
      transparent
    ) !important;
  }

  :deep(.oa-process-actions .ant-input),
  :deep(.oa-process-actions .ant-input-affix-wrapper),
  :deep(.oa-process-actions .ant-select-selector) {
    background: color-mix(
      in srgb,
      var(--oa-shell-surface-subtle) 92%,
      black 8%
    ) !important;
    color: var(--oa-ink) !important;
  }

  :deep(.oa-process-actions .ant-input::placeholder),
  :deep(.oa-process-actions .ant-select-selection-placeholder) {
    color: color-mix(in srgb, var(--oa-ink-soft) 84%, white 16%) !important;
  }
}

@media (max-width: 1200px) {
  .oa-lite-detail-grid {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 768px) {
  .oa-lite-process-head {
    flex-direction: column;
  }

  .oa-lite-detail-actions {
    justify-content: flex-start;
  }

  .oa-lite-process-name {
    font-size: 18px;
  }
}
</style>
