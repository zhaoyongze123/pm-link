<script lang="ts" setup>
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';
import type { SystemUserApi } from '#/api/system/user';

import { computed, h, nextTick, ref, shallowRef, watch } from 'vue';

import { prompt } from '@vben/common-ui';
import {
  BpmFieldPermissionType,
  BpmModelFormType,
  BpmModelType,
  BpmProcessInstanceStatus,
} from '@vben/constants';
import { formatDateTime } from '@vben/utils';

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
  recreate: [businessKey: string];
  refresh: [];
}>();

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
      return '已通过';
    }
    case BpmProcessInstanceStatus.CANCEL: {
      return '已取消';
    }
    case BpmProcessInstanceStatus.REJECT: {
      return '已驳回';
    }
    case BpmProcessInstanceStatus.RUNNING: {
      return '审批中';
    }
    default: {
      return '处理中';
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
      businessFormComponent.value = registerComponent(
        processDefinitionData.formCustomViewPath || '',
      );
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
  message.success('撤回成功');
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
        placeholder: '请输入取消原因',
        rows: 2,
      }),
    content: '请输入取消原因',
    modelPropName: 'value',
    title: '取消流程',
  }).then(async (reason) => {
    if (!reason) {
      return;
    }
    await cancelProcessInstanceByStartUser(processInstance.value!.id, reason);
    message.success('取消成功');
    emit('refresh');
  });
}

function handleRecreate() {
  if (!processInstance.value?.businessKey) {
    return;
  }
  emit('recreate', processInstance.value.businessKey);
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
                发起人：{{ processInstance.startUser?.nickname || '-' }}
              </span>
              <span>
                提交时间：{{ formatDateTime(processInstance.startTime || processInstance.createTime) }}
              </span>
            </div>
            <div class="oa-lite-process-id">
              流程编号：{{ processInstance.id || '-' }}
              <span class="oa-lite-process-id-divider">|</span>
              业务标识：{{ processInstance.businessKey || '-' }}
            </div>
          </div>

          <div class="oa-lite-detail-actions">
            <Button
              v-if="canWithdrawTask"
              class="oa-lite-white-button"
              @click="handleWithdraw"
            >
              撤回任务
            </Button>
            <Button
              v-if="canCancelProcess"
              class="oa-lite-white-button"
              @click="handleCancelProcess"
            >
              取消流程
            </Button>
            <Button
              v-if="canRecreateProcess"
              type="primary"
              class="oa-lite-white-primary"
              @click="handleRecreate"
            >
              重新发起
            </Button>
            <Tag v-if="showReadonlyChip" class="oa-lite-readonly-tag">
              仅查看
            </Tag>
          </div>
        </div>

        <div class="oa-lite-process-tabs">
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'form' }"
            @click="activeTab = 'form'"
          >
            审批详情
          </button>
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'diagram' }"
            @click="activeTab = 'diagram'"
          >
            流程图
          </button>
          <button
            class="oa-lite-process-tab"
            :class="{ active: activeTab === 'record' }"
            @click="activeTab = 'record'"
          >
            流转记录
          </button>
        </div>

        <div v-if="activeTab === 'form'" class="oa-lite-detail-grid">
          <section class="oa-lite-detail-card oa-lite-detail-card-form">
            <div class="oa-lite-detail-card-title">业务表单</div>
            <component
              :is="businessFormComponent"
              v-if="
                processDefinition.formType === BpmModelFormType.CUSTOM &&
                businessFormComponent
              "
              :id="String(processInstance.businessKey || '')"
              class="oa-lite-business-form"
            />
            <form-create
              v-else-if="processDefinition.formType === BpmModelFormType.NORMAL"
              v-model="normalForm.value"
              v-model:api="normalFormApi"
              :option="normalForm.option"
              :rule="normalForm.rule"
            />
            <Empty v-else description="暂无业务表单信息" />
          </section>

          <aside class="oa-lite-detail-card">
            <div class="oa-lite-detail-card-title">流程时间线</div>
            <ProcessInstanceTimeline :activity-nodes="activityNodes" />
          </aside>
        </div>

        <div v-else-if="activeTab === 'diagram'" class="oa-lite-detail-card">
          <div class="oa-lite-detail-card-title">流程图</div>
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
          <div class="oa-lite-detail-card-title">流转记录</div>
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
          <div class="oa-lite-detail-card-title">审批操作</div>
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
        <Empty description="请选择流程查看详情" />
      </div>
    </Spin>
  </div>
</template>

<style lang="scss" scoped>
.oa-lite-process-detail {
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
  font-weight: 700;
  color: #111827;
}

.oa-lite-process-desc-row {
  margin-top: 10px;
  display: flex;
  flex-wrap: wrap;
  gap: 10px 18px;
  font-size: 13px;
  color: #64748b;
}

.oa-lite-process-id {
  margin-top: 10px;
  font-size: 12px;
  color: #94a3b8;
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
  gap: 10px;
  border-bottom: 1px solid #e5e7eb;
  padding-bottom: 12px;
}

.oa-lite-process-tab {
  border: none;
  background: #f8fafc;
  color: #64748b;
  border-radius: 999px;
  padding: 8px 16px;
  cursor: pointer;
  transition: all 0.18s ease;
}

.oa-lite-process-tab.active {
  background: #111827;
  color: #fff;
}

.oa-lite-detail-grid {
  display: grid;
  grid-template-columns: minmax(0, 1.2fr) minmax(280px, 0.8fr);
  gap: 18px;
}

.oa-lite-detail-card {
  background: #fff;
  border-radius: 20px;
  border: 1px solid #e5ecf3;
  box-shadow: 0 10px 28px rgb(15 23 42 / 5%);
  padding: 20px;
  min-width: 0;
}

.oa-lite-detail-card-form {
  overflow: hidden;
}

.oa-lite-detail-card-title {
  font-size: 15px;
  font-weight: 700;
  color: #111827;
  margin-bottom: 16px;
}

.oa-lite-detail-empty {
  min-height: 320px;
  border-radius: 20px;
  border: 1px dashed #d8e1eb;
  background: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-operation-card {
  margin-top: 4px;
}

.oa-lite-operation-bar {
  :deep(.ant-btn) {
    border-radius: 12px;
  }
}

.oa-lite-status-chip {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 28px;
  border-radius: 999px;
  padding: 0 12px;
  font-size: 12px;
  font-weight: 600;
}

.oa-lite-status-chip.tone-primary {
  background: #eff6ff;
  color: #2563eb;
}

.oa-lite-status-chip.tone-success {
  background: #ecfdf3;
  color: #16a34a;
}

.oa-lite-status-chip.tone-danger {
  background: #fef2f2;
  color: #dc2626;
}

.oa-lite-status-chip.tone-muted,
.oa-lite-status-chip.tone-neutral {
  background: #f8fafc;
  color: #64748b;
}

.oa-lite-white-button,
.oa-lite-white-primary {
  border-radius: 12px;
}

.oa-lite-readonly-tag {
  border-radius: 999px;
  background: #eff6ff;
  color: #2563eb;
  border-color: #bfdbfe;
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
  :deep(.ant-timeline-item-content) {
    color: #111827 !important;
  }

  :deep(.bg-card) {
    background: #fff !important;
    border: 1px solid #e5ecf3;
    border-radius: 14px;
  }

  :deep(.simple-process-model-container) {
    border: 1px solid #e5ecf3;
    border-radius: 18px;
    overflow: hidden;
  }

  :deep(.simple-process-model-container .ant-btn),
  :deep(.simple-process-model-container .ant-btn > span),
  :deep(.simple-process-model-container .ant-btn .iconify) {
    color: #111827 !important;
  }

  :deep(.simple-process-model-container .ant-btn) {
    background: #fff !important;
    border-color: #dbe5f0 !important;
    box-shadow: none !important;
  }

  :deep(.vxe-table--render-default),
  :deep(.vxe-table--render-default .vxe-table--header-wrapper),
  :deep(.vxe-table--render-default .vxe-table--body-wrapper),
  :deep(.vxe-table--render-default .vxe-body--column),
  :deep(.vxe-table--render-default .vxe-header--column) {
    background: #fff !important;
  }

  :deep(.vxe-table--render-default .vxe-cell),
  :deep(.vxe-table--render-default .vxe-table--empty-content) {
    color: #111827 !important;
  }

  :deep(.vxe-table--render-default .vxe-header--column .vxe-cell) {
    color: #475569 !important;
    font-weight: 600;
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
