<script lang="ts" setup>
import type { BpmCategoryApi } from '#/api/bpm/category';
import type { BpmProcessDefinitionApi } from '#/api/bpm/definition';
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';
import type { BpmTaskApi } from '#/api/bpm/task';
import type { SystemUserApi } from '#/api/system/user';
import type { NotificationItem } from '@vben/layouts';

import {
  computed,
  nextTick,
  onMounted,
  onUnmounted,
  reactive,
  ref,
  watch,
} from 'vue';

import {
  BpmCandidateStrategyEnum,
  BpmNodeIdEnum,
  BpmProcessInstanceStatus,
} from '@vben/constants';
import { VbenFullScreen } from '@vben/common-ui';
import { getDictOptions } from '@vben/hooks';
import {
  AntdProfileOutlined,
  IconifyIcon,
} from '@vben/icons';
import {
  LanguageToggle,
  Notification,
  ThemeToggle,
  TimezoneButton,
  UserDropdown,
} from '@vben/layouts';
import { preferences } from '@vben/preferences';
import { useUserStore } from '@vben/stores';
import { formatDateTime, formatPast2 } from '@vben/utils';

import {
  Button,
  ConfigProvider,
  DatePicker,
  Empty,
  Form,
  Input,
  message,
  Pagination,
  Select,
  Spin,
  Tag,
  theme as antdTheme,
} from 'ant-design-vue';
import dayjs from 'dayjs';

import { getCategorySimpleList } from '#/api/bpm/category';
import { getProcessDefinition } from '#/api/bpm/definition';
import { createLeave, getLeave } from '#/api/bpm/oa/leave';
import {
  getApprovalDetail,
  getProcessInstanceCopyPage,
  getProcessInstanceMyPage,
} from '#/api/bpm/processInstance';
import {
  getUnreadNotifyMessageCount,
  getUnreadNotifyMessageList,
  updateAllNotifyMessageRead,
  updateNotifyMessageRead,
} from '#/api/system/notify/message';
import { getUserProfile } from '#/api/system/user/profile';
import { router } from '#/router';
import { getSimpleUserList } from '#/api/system/user';
import { getTaskDonePage, getTaskTodoPage } from '#/api/bpm/task';
import { useAuthStore } from '#/store';
import ProcessInstanceTimeline from '#/views/bpm/processInstance/detail/modules/time-line.vue';
import ProfileCenter from '#/views/_core/profile/index.vue';
import ProcessDetail, {
  type OaLiteDetailRequest,
  type OaLiteDetailSection,
} from './components/process-detail.vue';

defineOptions({ name: 'OALiteHome' });

type MainTab = 'create' | 'copied' | 'initiated' | 'pending' | 'processed';
type ListTab = Exclude<MainTab, 'create'>;
type ViewState = 'leave-form' | 'main' | 'profile';
type DateRangeValue = [string, string];

interface ListFilterState {
  category?: string;
  createTime?: DateRangeValue;
  name: string;
  processDefinitionId?: string;
  processDefinitionKey?: string;
  status?: number;
}

interface ListPageState {
  pageNo: number;
  pageSize: number;
  total: number;
}

interface LeaveFormState {
  endTime: string;
  reason: string;
  startTime: string;
  startUserSelectAssignees: Record<string, number[]>;
  type?: number;
}

interface SelectOption {
  label: string;
  value: number | string;
}

type DetailPayload =
  | BpmTaskApi.Task
  | BpmProcessInstanceApi.ProcessInstance
  | BpmProcessInstanceApi.ProcessInstanceCopyRespVO
  | null;

const LEAVE_PROCESS_KEY = 'oa_leave';
const DEFAULT_PAGE_SIZE = 20;
const listTabs: ListTab[] = ['initiated', 'pending', 'processed', 'copied'];

const authStore = useAuthStore();
const userStore = useUserStore();

const loading = ref(false);
const leaveSubmitting = ref(false);
const leavePublishing = ref(false);
const activeTab = ref<MainTab>('create');
const lastCenterTab = ref<ListTab>('pending');
const viewState = ref<ViewState>('main');
const selectedCreateCategoryCode = ref<string>();
const selectedItem = ref<DetailPayload>(null);
const categories = ref<BpmCategoryApi.Category[]>([]);
const leaveProcessDefinition = ref<BpmProcessDefinitionApi.ProcessDefinition | null>(
  null,
);
const selectableUsers = ref<SystemUserApi.User[]>([]);
const activityNodes = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const startUserSelectTasks = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const timelineRef = ref<any>();
const todoItems = ref<BpmTaskApi.Task[]>([]);
const doneItems = ref<BpmTaskApi.Task[]>([]);
const initiatedItems = ref<BpmProcessInstanceApi.ProcessInstance[]>([]);
const copiedItems = ref<BpmProcessInstanceApi.ProcessInstanceCopyRespVO[]>([]);
const OA_LITE_BODY_THEME_CLASS = 'oa-lite-light-theme';
const headerNotifications = ref<NotificationItem[]>([]);
const headerUnreadCount = ref(0);
const showNotificationDot = computed(() => headerUnreadCount.value > 0);
let notificationPollingTimer: null | ReturnType<typeof setInterval> = null;

const oaLiteTheme = {
  algorithm: [antdTheme.defaultAlgorithm],
  token: {
    colorBgBase: '#ffffff',
    colorBgContainer: '#ffffff',
    colorBgElevated: '#ffffff',
    colorBorder: '#dbe5f0',
    colorBorderSecondary: '#e5edf5',
    colorFillSecondary: '#f8fafc',
    colorFillTertiary: '#f1f5f9',
    colorPrimary: '#2563eb',
    colorPrimaryActive: '#1e40af',
    colorPrimaryHover: '#1d4ed8',
    colorSplit: '#e5e7eb',
    colorText: '#111827',
    colorTextQuaternary: '#94a3b8',
    colorTextSecondary: '#475569',
    colorTextTertiary: '#64748b',
  },
};

const headerMenus = computed(() => [
  {
    handler: () => {
      openProfileCenter();
    },
    icon: AntdProfileOutlined,
    text: '个人中心',
  },
]);

const avatar = computed(
  () => userStore.userInfo?.avatar ?? preferences.app.defaultAvatar,
);

async function syncCurrentUserProfile() {
  const profile = await getUserProfile().catch(() => null);
  if (!profile) {
    return;
  }
  userStore.setUserInfo({
    ...(userStore.userInfo ?? {}),
    avatar: profile?.avatar || userStore.userInfo?.avatar || '',
    email: profile?.email ?? userStore.userInfo?.email,
    nickname: profile?.nickname ?? userStore.userInfo?.nickname ?? '',
    userId:
      String(userStore.userInfo?.userId ?? profile?.id ?? '') || '',
    username: profile?.username ?? userStore.userInfo?.username ?? '',
  });
}

const tabLoading = reactive<Record<ListTab, boolean>>({
  copied: false,
  initiated: false,
  pending: false,
  processed: false,
});
const tabInitialized = reactive<Record<ListTab, boolean>>({
  copied: false,
  initiated: false,
  pending: false,
  processed: false,
});
const tabPages = reactive<Record<ListTab, ListPageState>>({
  copied: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  initiated: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  pending: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  processed: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
});

const leaveForm = reactive<LeaveFormState>({
  endTime: '',
  reason: '',
  startTime: '',
  startUserSelectAssignees: {},
  type: undefined,
});

function createDefaultFilter(): ListFilterState {
  return {
    category: undefined,
    createTime: undefined,
    name: '',
    processDefinitionId: leaveProcessDefinition.value?.id,
    processDefinitionKey: LEAVE_PROCESS_KEY,
    status: undefined,
  };
}

const listFilters = reactive<Record<ListTab, ListFilterState>>({
  copied: createDefaultFilter(),
  initiated: createDefaultFilter(),
  pending: createDefaultFilter(),
  processed: createDefaultFilter(),
});

function normalizeDictOptions(dictType: string) {
  return getDictOptions(dictType, 'number')
    .filter(
      (item) =>
        typeof item.value === 'number' || typeof item.value === 'string',
    )
    .map((item) => ({
      label: String(item.label),
      value: item.value as number | string,
    })) as SelectOption[];
}

const leaveTypeOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_oa_leave_type'),
);
const processStatusOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_process_instance_status'),
);
const taskStatusOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_task_status'),
);
const categoryOptions = computed<SelectOption[]>(() =>
  categories.value.map((item) => ({
    label: item.name,
    value: item.code,
  })),
);
const processTemplateIdOptions = computed<SelectOption[]>(() =>
  leaveProcessDefinition.value
    ? [
        {
          label: leaveProcessDefinition.value.name,
          value: leaveProcessDefinition.value.id,
        },
      ]
    : [],
);
const processTemplateKeyOptions = computed<SelectOption[]>(() =>
  leaveProcessDefinition.value
    ? [
        {
          label: leaveProcessDefinition.value.name,
          value: LEAVE_PROCESS_KEY,
        },
      ]
    : [],
);
const currentStatusOptions = computed<SelectOption[]>(() =>
  activeTab.value === 'processed'
    ? taskStatusOptions.value
    : processStatusOptions.value,
);
const currentProcessOptions = computed<SelectOption[]>(() =>
  activeTab.value === 'copied'
    ? processTemplateIdOptions.value
    : processTemplateKeyOptions.value,
);
const currentProcessFilterValue = computed<string | undefined>({
  get() {
    if (activeTab.value === 'create') {
      return undefined;
    }
    return activeTab.value === 'copied'
      ? listFilters.copied.processDefinitionId
      : listFilters[activeTab.value].processDefinitionKey;
  },
  set(value) {
    if (activeTab.value === 'create') {
      return;
    }
    if (activeTab.value === 'copied') {
      listFilters.copied.processDefinitionId = value;
      return;
    }
    listFilters[activeTab.value].processDefinitionKey = value;
  },
});

const currentFilter = computed(() =>
  activeTab.value === 'create' ? null : listFilters[activeTab.value],
);
const currentPageState = computed(() =>
  activeTab.value === 'create' ? null : tabPages[activeTab.value],
);
const currentListLoading = computed(() =>
  activeTab.value === 'create' ? false : tabLoading[activeTab.value],
);
const currentDetailSection = computed<OaLiteDetailSection>(() =>
  activeTab.value === 'create' ? 'initiated' : activeTab.value,
);

const stats = computed(() => ({
  copied: tabPages.copied.total,
  initiated: tabPages.initiated.total,
  pending: tabPages.pending.total,
  processed: tabPages.processed.total,
}));

const createCategoryTabs = computed<BpmCategoryApi.Category[]>(() => {
  const list = [...categories.value];
  const leaveCategoryCode = leaveProcessDefinition.value?.category;
  if (
    leaveCategoryCode &&
    !list.some((item) => item.code === leaveCategoryCode)
  ) {
    list.push({
      code: leaveCategoryCode,
      description: undefined,
      id: -1,
      name: leaveProcessDefinition.value?.categoryName || '未分类',
      sort: list.length,
      status: 0,
    });
  }
  return list;
});

const currentCreateCategoryCode = computed(
  () => selectedCreateCategoryCode.value,
);

const currentCreateCategoryName = computed(() => {
  const currentCategory = createCategoryTabs.value.find(
    (item) => item.code === currentCreateCategoryCode.value,
  );
  if (currentCategory) {
    return currentCategory.name;
  }
  return leaveProcessDefinition.value?.categoryName || '流程分类';
});

const showLeaveCreateCard = computed(() => {
  const leaveCategoryCode = leaveProcessDefinition.value?.category;
  if (!leaveProcessDefinition.value) {
    return false;
  }
  if (!currentCreateCategoryCode.value || !leaveCategoryCode) {
    return true;
  }
  return currentCreateCategoryCode.value === leaveCategoryCode;
});

const dashboardNavItems = computed(() => [
  {
    count: stats.value.pending,
    icon: 'lucide:list-todo',
    key: 'pending' as ListTab,
    label: '待处理的',
  },
  {
    count: stats.value.processed,
    icon: 'lucide:badge-check',
    key: 'processed' as ListTab,
    label: '已处理的',
  },
  {
    count: stats.value.initiated,
    icon: 'lucide:file-text',
    key: 'initiated' as ListTab,
    label: '我发起的',
  },
  {
    count: stats.value.copied,
    icon: 'lucide:send',
    key: 'copied' as ListTab,
    label: '抄送我的',
  },
]);

const topNavKey = computed<'center' | 'create'>(() =>
  activeTab.value === 'create' ? 'create' : 'center',
);

const currentListTitle = computed(() => {
  switch (activeTab.value) {
    case 'copied': {
      return '抄送我的';
    }
    case 'initiated': {
      return '我的流程';
    }
    case 'pending': {
      return '待办任务';
    }
    case 'processed': {
      return '已办任务';
    }
    default: {
      return '发起流程';
    }
  }
});

const currentListSubtitle = computed(() => {
  switch (activeTab.value) {
    case 'copied': {
      return '保留管理端抄送能力，支持查看抄送节点、意见和时间';
    }
    case 'initiated': {
      return '保留管理端我的流程能力，支持状态筛选、取消和重新发起';
    }
    case 'pending': {
      return '保留管理端待办能力，支持进入真实审批详情并办理';
    }
    case 'processed': {
      return '保留管理端已办能力，支持查看历史和撤回任务';
    }
    default: {
      return '选择模板并发起真实审批流程';
    }
  }
});

const showProcessFilter = computed(
  () =>
    activeTab.value === 'initiated' ||
    activeTab.value === 'pending' ||
    activeTab.value === 'processed',
);
const showCategoryFilter = computed(
  () =>
    activeTab.value === 'initiated' ||
    activeTab.value === 'pending' ||
    activeTab.value === 'processed',
);
const showStatusFilter = computed(
  () => activeTab.value === 'initiated' || activeTab.value === 'processed',
);

const currentList = computed(() => {
  if (activeTab.value === 'create') {
    return [];
  }
  return getListSource(activeTab.value);
});

const currentDetailRequest = computed<null | OaLiteDetailRequest>(() => {
  if (!selectedItem.value) {
    return null;
  }
  if (isTaskItem(selectedItem.value)) {
    return {
      businessKey: selectedItem.value.processInstance?.businessKey,
      processInstanceId: String(
        selectedItem.value.processInstance?.id || selectedItem.value.processInstanceId,
      ),
      taskId: selectedItem.value.id,
    };
  }
  if (isCopiedItem(selectedItem.value)) {
    return {
      activityId: selectedItem.value.activityId || undefined,
      processInstanceId: String(selectedItem.value.processInstanceId),
      taskId: selectedItem.value.taskId || undefined,
    };
  }
  return {
    businessKey: selectedItem.value.businessKey,
    processInstanceId: String(selectedItem.value.id),
  };
});

function isTaskItem(item: DetailPayload): item is BpmTaskApi.Task {
  return Boolean(item && 'processInstance' in item);
}

function isCopiedItem(
  item: DetailPayload,
): item is BpmProcessInstanceApi.ProcessInstanceCopyRespVO {
  return Boolean(item && 'processInstanceId' in item && 'activityName' in item);
}

function getListSource(tab: ListTab) {
  switch (tab) {
    case 'copied': {
      return copiedItems.value;
    }
    case 'initiated': {
      return initiatedItems.value;
    }
    case 'pending': {
      return todoItems.value;
    }
    case 'processed': {
      return doneItems.value;
    }
  }
}

function getItemIdentity(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isCopiedItem(item)) {
    return `copy-${item.id}-${item.processInstanceId}-${item.activityId}`;
  }
  if (isTaskItem(item)) {
    return `task-${item.id}`;
  }
  return `process-${item.id}`;
}

function syncSelectedItem(tab: ListTab) {
  const list = getListSource(tab);
  const currentIdentity = getItemIdentity(selectedItem.value);
  const found = currentIdentity
    ? list.find((item) => getItemIdentity(item) === currentIdentity)
    : undefined;
  selectedItem.value = found || list[0] || null;
}

function getSummaryText(summary?: { key: string; value: string }[]) {
  if (!summary?.length) {
    return '暂无摘要';
  }
  return summary.map((item) => `${item.key}：${item.value}`).join(' / ');
}

function getProcessStatusText(status?: number) {
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

function getTaskStatusText(status?: number) {
  const option = taskStatusOptions.value.find((item) => item.value === status);
  return option?.label || '已处理';
}

function getItemStatus(item: DetailPayload) {
  if (!item) {
    return undefined;
  }
  if (isTaskItem(item)) {
    return activeTab.value === 'processed'
      ? item.status
      : item.processInstance?.status;
  }
  if (isCopiedItem(item)) {
    return undefined;
  }
  return item.status;
}

function getItemStatusText(item: DetailPayload) {
  if (!item) {
    return '';
  }
  const status = getItemStatus(item);
  if (status === undefined) {
    return '';
  }
  return isTaskItem(item) && activeTab.value === 'processed'
    ? getTaskStatusText(status)
    : getProcessStatusText(status);
}

function getItemTitle(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return item.processInstance?.name || '';
  }
  if (isCopiedItem(item)) {
    return item.processInstanceName || '';
  }
  return item.name || '';
}

function getItemSummary(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return getSummaryText(item.processInstance?.summary as any);
  }
  if (isCopiedItem(item)) {
    return getSummaryText(item.summary as any);
  }
  return getSummaryText(item.summary);
}

function getItemMetaLeft(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return `当前任务：${item.name}`;
  }
  if (isCopiedItem(item)) {
    return `抄送节点：${item.activityName || '-'}`;
  }
  if (
    item.status === BpmProcessInstanceStatus.RUNNING &&
    item.tasks &&
    item.tasks.length > 0
  ) {
    const firstTask = item.tasks[0];
    if (!firstTask) {
      return getProcessStatusText(item.status);
    }
    if (item.tasks.length === 1) {
      return `${firstTask.assigneeUser?.nickname || '审批人'}（${firstTask.name}）审批中`;
    }
    return `${firstTask.assigneeUser?.nickname || '审批人'} 等 ${item.tasks.length} 人（${firstTask.name}）审批中`;
  }
  return getProcessStatusText(item.status);
}

function getItemMetaRight(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return activeTab.value === 'processed'
      ? `完成时间：${formatDateTime(item.endTime || item.createTime)}`
      : `任务时间：${formatDateTime(item.createTime)}`;
  }
  if (isCopiedItem(item)) {
    return `抄送时间：${formatDateTime(item.createTime)}`;
  }
  return activeTab.value === 'initiated'
    ? `发起时间：${formatDateTime(item.startTime || item.createTime)}`
    : `结束时间：${formatDateTime(item.endTime || item.createTime)}`;
}

function getExtraMetaRows(item: DetailPayload) {
  if (!item) {
    return [] as string[];
  }
  if (isCopiedItem(item)) {
    return [
      `流程发起人：${item.startUser?.nickname || '-'}`,
      `抄送人：${item.createUser?.nickname || '-'}`,
      `抄送意见：${item.reason || '-'}`,
    ];
  }
  if (isTaskItem(item)) {
    if (activeTab.value === 'processed') {
      return [
        `发起人：${item.processInstance?.startUser?.nickname || '-'}`,
        `审批意见：${item.reason || '-'}`,
        `耗时：${formatPast2(item.durationInMillis || 0)}`,
      ];
    }
    return [
      `发起人：${item.processInstance?.startUser?.nickname || '-'}`,
      `流程编号：${item.processInstanceId}`,
      `任务编号：${item.id}`,
    ];
  }
  return [
    `流程分类：${item.categoryName || item.category || '-'}`,
    `业务标识：${item.businessKey || '-'}`,
    `流程编号：${item.id}`,
  ];
}

function getKeywordPlaceholder() {
  switch (activeTab.value) {
    case 'copied': {
      return '请输入流程名称';
    }
    case 'initiated': {
      return '请输入流程名称';
    }
    case 'pending': {
      return '请输入任务名称';
    }
    case 'processed': {
      return '请输入任务名称';
    }
    default: {
      return '请输入关键字';
    }
  }
}

function getCreateTimePlaceholder(): [string, string] {
  return activeTab.value === 'copied'
    ? ['开始抄送时间', '结束抄送时间']
    : ['开始发起时间', '结束发起时间'];
}

function getTabErrorMessage(tab: ListTab) {
  switch (tab) {
    case 'copied': {
      return '加载抄送流程失败';
    }
    case 'initiated': {
      return '加载我的流程失败';
    }
    case 'pending': {
      return '加载待办任务失败';
    }
    case 'processed': {
      return '加载已办任务失败';
    }
  }
}

function applyLeaveDefinitionFilterDefaults() {
  if (!leaveProcessDefinition.value?.id) {
    return;
  }
  listTabs.forEach((tab) => {
    if (tab === 'copied' && !listFilters[tab].processDefinitionId) {
      listFilters[tab].processDefinitionId = leaveProcessDefinition.value!.id;
    }
    if (tab !== 'copied' && !listFilters[tab].processDefinitionKey) {
      listFilters[tab].processDefinitionKey = LEAVE_PROCESS_KEY;
    }
  });
}

function getLeaveProcessVariables() {
  if (!leaveForm.startTime || !leaveForm.endTime) {
    return {};
  }
  const day = dayjs(Number(leaveForm.endTime)).diff(
    dayjs(Number(leaveForm.startTime)),
    'day',
  );
  return { day };
}

function isStartUserSelectableNode(node: BpmProcessInstanceApi.ApprovalNodeInfo) {
  return node.candidateStrategy === BpmCandidateStrategyEnum.START_USER_SELECT;
}

function syncTimelineCustomUsers() {
  if (!timelineRef.value?.batchSetCustomApproveUsers) {
    return;
  }
  const selectedUserMap = Object.entries(leaveForm.startUserSelectAssignees).reduce<
    Record<string, SystemUserApi.User[]>
  >((acc, [activityId, userIds]) => {
    if (!Array.isArray(userIds) || userIds.length === 0) {
      acc[activityId] = [];
      return acc;
    }
    const activityNode = activityNodes.value.find((node) => node.id === activityId);
    const activityCandidates = activityNode?.candidateUsers || [];
    acc[activityId] = userIds
      .map((userId) => {
        return (
          activityCandidates.find((candidate) => candidate.id === userId) ||
          selectableUsers.value.find((user) => user.id === userId)
        );
      })
      .filter(Boolean) as SystemUserApi.User[];
    return acc;
  }, {});
  timelineRef.value.batchSetCustomApproveUsers(selectedUserMap);
}

function handleStartUserSelectConfirm(activityId: string, userList: SystemUserApi.User[]) {
  leaveForm.startUserSelectAssignees[activityId] = (userList || []).map(
    (user) => Number(user.id),
  );
  syncTimelineCustomUsers();
}

async function loadLeaveDefinition() {
  leaveProcessDefinition.value = await getProcessDefinition(
    undefined,
    LEAVE_PROCESS_KEY,
  );
}

async function loadBaseOptions() {
  const [categoryList, userList] = await Promise.all([
    getCategorySimpleList(),
    getSimpleUserList(),
  ]);
  categories.value = categoryList;
  selectableUsers.value = userList;
}

async function loadLeaveApprovalPreview() {
  if (!leaveProcessDefinition.value?.id) {
    activityNodes.value = [];
    startUserSelectTasks.value = [];
    await nextTick();
    syncTimelineCustomUsers();
    return;
  }
  const data = await getApprovalDetail({
    processDefinitionId: leaveProcessDefinition.value.id,
    activityId: BpmNodeIdEnum.START_USER_NODE_ID,
    processVariablesStr: JSON.stringify(getLeaveProcessVariables()),
  });
  activityNodes.value = data?.activityNodes || [];
  startUserSelectTasks.value = activityNodes.value.filter((node) =>
    isStartUserSelectableNode(node),
  );
  const nextAssignees: Record<string, number[]> = {};
  startUserSelectTasks.value.forEach((node) => {
    nextAssignees[node.id] = leaveForm.startUserSelectAssignees[node.id] || [];
  });
  leaveForm.startUserSelectAssignees = nextAssignees;
  await nextTick();
  syncTimelineCustomUsers();
}

async function loadTabData(tab: ListTab) {
  tabLoading[tab] = true;
  try {
    const pageState = tabPages[tab];
    const filter = listFilters[tab];
    const createTime = filter.createTime ? [...filter.createTime] : undefined;

    switch (tab) {
      case 'initiated': {
        const resp = await getProcessInstanceMyPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          status: filter.status,
          createTime,
        });
        initiatedItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
      case 'pending': {
        const resp = await getTaskTodoPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          createTime,
        });
        todoItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
      case 'processed': {
        const resp = await getTaskDonePage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          status: filter.status,
          createTime,
        });
        doneItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
      case 'copied': {
        const resp = await getProcessInstanceCopyPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          processInstanceName: filter.name.trim() || undefined,
          processDefinitionId: filter.processDefinitionId,
          createTime,
        });
        copiedItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
    }
    tabInitialized[tab] = true;
    if (activeTab.value === tab) {
      syncSelectedItem(tab);
    }
  } catch (error: any) {
    message.error(error?.message || getTabErrorMessage(tab));
  } finally {
    tabLoading[tab] = false;
  }
}

async function refreshAllTabs() {
  loading.value = true;
  try {
    await Promise.all(listTabs.map((tab) => loadTabData(tab)));
  } finally {
    loading.value = false;
  }
}

function resetLeaveForm() {
  leaveForm.type = undefined;
  leaveForm.startTime = '';
  leaveForm.endTime = '';
  leaveForm.reason = '';
  leaveForm.startUserSelectAssignees = {};
}

async function openLeaveForm(businessKey?: string) {
  if (!leaveProcessDefinition.value) {
    await loadLeaveDefinition();
  }
  if (!leaveProcessDefinition.value) {
    message.error('OA 请假的流程模型未配置，请检查！');
    return;
  }
  resetLeaveForm();
  leavePublishing.value = true;
  try {
    if (businessKey) {
      const leaveId = Number(businessKey);
      if (!Number.isNaN(leaveId) && leaveId > 0) {
        const detail = await getLeave(leaveId);
        leaveForm.type = detail.type;
        leaveForm.startTime = String(detail.startTime);
        leaveForm.endTime = String(detail.endTime);
        leaveForm.reason = detail.reason || '';
      }
    }
    await loadLeaveApprovalPreview();
    viewState.value = 'leave-form';
  } finally {
    leavePublishing.value = false;
  }
}

async function submitLeave() {
  if (!leaveProcessDefinition.value) {
    message.error('OA 请假的流程模型未配置，无法发起流程');
    return;
  }
  if (
    leaveForm.type === undefined ||
    !leaveForm.startTime ||
    !leaveForm.endTime ||
    !leaveForm.reason.trim()
  ) {
    message.warning('请完整填写请假信息');
    return;
  }
  for (const node of startUserSelectTasks.value) {
    const assignees = leaveForm.startUserSelectAssignees[node.id] || [];
    if (
      isStartUserSelectableNode(node) &&
      assignees.length === 0
    ) {
      message.warning(`请选择${node.name}的审批人`);
      return;
    }
  }
  leaveSubmitting.value = true;
  try {
    await createLeave({
      endTime: Number(leaveForm.endTime),
      reason: leaveForm.reason.trim(),
      startTime: Number(leaveForm.startTime),
      startUserSelectAssignees: leaveForm.startUserSelectAssignees,
      type: leaveForm.type,
    });
    message.success('请假流程已发起');
    viewState.value = 'main';
    activeTab.value = 'initiated';
    tabPages.initiated.pageNo = 1;
    await refreshAllTabs();
    syncSelectedItem('initiated');
  } finally {
    leaveSubmitting.value = false;
  }
}

async function handleNotificationGetUnreadCount() {
  headerUnreadCount.value = await getUnreadNotifyMessageCount();
}

async function handleNotificationGetList() {
  const list = await getUnreadNotifyMessageList();
  headerNotifications.value = list.map((item) => ({
    avatar: preferences.app.defaultAvatar,
    date: formatDateTime(item.createTime) as string,
    id: item.id,
    isRead: false,
    message: item.templateContent,
    title: item.templateNickname,
  }));
}

function handleNotificationViewAll() {
  router.push({
    name: 'MyNotifyMessage',
  });
}

async function handleNotificationMakeAll() {
  await updateAllNotifyMessageRead();
  headerUnreadCount.value = 0;
  headerNotifications.value = [];
}

async function handleNotificationClear() {
  await handleNotificationMakeAll();
}

async function handleNotificationRead(item: NotificationItem) {
  if (!item.id) {
    return;
  }
  await updateNotifyMessageRead([item.id]);
  await handleNotificationGetUnreadCount();
  headerNotifications.value = headerNotifications.value.filter(
    (notificationItem) => notificationItem.id !== item.id,
  );
}

function handleNotificationOpen(open: boolean) {
  if (!open) {
    return;
  }
  handleNotificationGetList();
  handleNotificationGetUnreadCount();
}

async function handleLogout() {
  await authStore.logout(false);
}

function openProfileCenter() {
  viewState.value = 'profile';
}

function selectCreateCategory(code: string) {
  selectedCreateCategoryCode.value = code;
}

function openTab(tab: MainTab) {
  activeTab.value = tab;
  viewState.value = 'main';
}

async function handleFilterSubmit() {
  if (activeTab.value === 'create') {
    return;
  }
  tabPages[activeTab.value].pageNo = 1;
  await loadTabData(activeTab.value);
}

async function resetCurrentFilter() {
  if (activeTab.value === 'create') {
    return;
  }
  Object.assign(listFilters[activeTab.value], createDefaultFilter());
  tabPages[activeTab.value].pageNo = 1;
  await loadTabData(activeTab.value);
}

async function handlePageChange(page: number, pageSize: number) {
  if (activeTab.value === 'create') {
    return;
  }
  const pageState = tabPages[activeTab.value];
  pageState.pageNo = page;
  pageState.pageSize = pageSize;
  await loadTabData(activeTab.value);
}

async function handleDetailRefresh() {
  await refreshAllTabs();
  if (activeTab.value !== 'create') {
    syncSelectedItem(activeTab.value);
  }
}

function openMainNav(section: 'center' | 'create') {
  if (section === 'create') {
    openTab('create');
    return;
  }
  openTab(activeTab.value === 'create' ? lastCenterTab.value : activeTab.value);
}

watch(
  [createCategoryTabs, () => leaveProcessDefinition.value?.category],
  ([tabs, leaveCategoryCode]) => {
    if (tabs.length === 0) {
      selectedCreateCategoryCode.value = leaveCategoryCode;
      return;
    }
    if (
      selectedCreateCategoryCode.value &&
      tabs.some((item) => item.code === selectedCreateCategoryCode.value)
    ) {
      return;
    }
    selectedCreateCategoryCode.value =
      leaveCategoryCode && tabs.some((item) => item.code === leaveCategoryCode)
        ? leaveCategoryCode
        : tabs[0].code;
  },
  {
    immediate: true,
  },
);

watch(
  () => [leaveForm.type, leaveForm.startTime, leaveForm.endTime],
  async () => {
    if (viewState.value !== 'leave-form' || !leaveProcessDefinition.value) {
      return;
    }
    await loadLeaveApprovalPreview();
  },
);

watch(
  () => activeTab.value,
  async (tab) => {
    if (tab !== 'create') {
      lastCenterTab.value = tab;
    }
    if (tab === 'create') {
      selectedItem.value = null;
      return;
    }
    if (!tabInitialized[tab]) {
      await loadTabData(tab);
      return;
    }
    syncSelectedItem(tab);
  },
);

onMounted(async () => {
  if (typeof document !== 'undefined') {
    document.body.classList.add(OA_LITE_BODY_THEME_CLASS);
  }
  try {
    await Promise.all([
      loadBaseOptions(),
      loadLeaveDefinition(),
      syncCurrentUserProfile(),
    ]);
    await handleNotificationGetUnreadCount();
    notificationPollingTimer = setInterval(() => {
      if (userStore.userInfo) {
        handleNotificationGetUnreadCount();
      }
    }, 1000 * 60 * 2);
    if (!leaveProcessDefinition.value) {
      message.error('OA 请假的流程模型未配置，请检查！');
      return;
    }
    applyLeaveDefinitionFilterDefaults();
    await refreshAllTabs();
  } catch (error: any) {
    message.error(error?.message || '加载 OA 用户审批页失败');
  }
});

onUnmounted(() => {
  if (typeof document !== 'undefined') {
    document.body.classList.remove(OA_LITE_BODY_THEME_CLASS);
  }
  if (notificationPollingTimer) {
    clearInterval(notificationPollingTimer);
    notificationPollingTimer = null;
  }
});
</script>

<template>
  <ConfigProvider :theme="oaLiteTheme">
    <div class="oa-lite-page">
      <div class="oa-lite-bg"></div>

      <template v-if="viewState === 'leave-form'">
        <div class="oa-lite-leave-page">
          <header class="oa-lite-leave-header">
            <div class="oa-lite-leave-left">
              <button class="oa-lite-leave-back" @click="viewState = 'main'">
                <IconifyIcon icon="lucide:chevron-left" />
              </button>
              <div class="oa-lite-leave-header-tabs">
                <div class="oa-lite-leave-header-tab active">发起审批</div>
              </div>
            </div>
          </header>

          <main class="oa-lite-leave-main">
            <div class="oa-lite-leave-shell">
              <div class="oa-lite-leave-card">
                <div class="oa-lite-leave-title-row">
                  <div>
                    <h1 class="oa-lite-leave-title">请假</h1>
                    <p class="oa-lite-leave-subtitle">真实 BPM 流程发起</p>
                  </div>
                  <IconifyIcon icon="lucide:file-heart" class="oa-lite-leave-qr" />
                </div>

                <div class="oa-lite-leave-divider"></div>

                <Form layout="vertical">
                  <Form.Item label="请假类型" required>
                    <Select
                      v-model:value="leaveForm.type"
                      :options="leaveTypeOptions"
                      placeholder="请选择请假类型"
                      popup-class-name="oa-lite-select-popup"
                      :get-popup-container="(triggerNode) => triggerNode.parentNode"
                    />
                  </Form.Item>
                  <Form.Item label="开始时间" required>
                    <DatePicker
                      v-model:value="leaveForm.startTime"
                      show-time
                      value-format="x"
                      format="YYYY-MM-DD HH:mm:ss"
                      class="w-full"
                      placeholder="请选择开始时间"
                    />
                  </Form.Item>
                  <Form.Item label="结束时间" required>
                    <DatePicker
                      v-model:value="leaveForm.endTime"
                      show-time
                      value-format="x"
                      format="YYYY-MM-DD HH:mm:ss"
                      class="w-full"
                      placeholder="请选择结束时间"
                    />
                  </Form.Item>
                  <Form.Item label="请假原因" required>
                    <Input.TextArea
                      v-model:value="leaveForm.reason"
                      :rows="4"
                      placeholder="请输入请假原因"
                    />
                  </Form.Item>
                </Form>
              </div>

              <div class="oa-lite-leave-card">
                <div class="oa-lite-leave-flow-head">
                  <div class="oa-lite-leave-flow-title">流程</div>
                  <div class="oa-lite-leave-flow-tag">按管理端真实配置加载</div>
                </div>

                <div class="oa-lite-leave-flow-body">
                  <ProcessInstanceTimeline
                    ref="timelineRef"
                    :activity-nodes="activityNodes"
                    :show-status-icon="false"
                    @select-user-confirm="handleStartUserSelectConfirm"
                  />
                </div>

                <div class="oa-lite-leave-submit-row">
                  <Button type="primary" :loading="leaveSubmitting" @click="submitLeave">
                    提交
                  </Button>
                </div>
              </div>
            </div>
          </main>
        </div>
      </template>

      <template v-else>
        <header class="oa-lite-topbar">
          <div class="oa-lite-topbar-inner">
            <div class="oa-lite-brand">
              <div class="oa-lite-brand-icon">
                <IconifyIcon icon="lucide:file-heart" />
              </div>
              <div>
                <div class="oa-lite-brand-title">OA 审批</div>
                <div class="oa-lite-brand-subtitle">普通用户审批工作台</div>
              </div>
            </div>

            <nav class="oa-lite-topnav">
              <button
                class="oa-lite-topnav-tab"
                :class="{ active: topNavKey === 'create' }"
                @click="openMainNav('create')"
              >
                发起审批
              </button>
              <button
                class="oa-lite-topnav-tab"
                :class="{ active: topNavKey === 'center' }"
                @click="openMainNav('center')"
              >
                审批中心
              </button>
            </nav>

            <div class="oa-lite-user-actions">
              <Button class="oa-lite-white-button oa-lite-refresh-button" @click="handleDetailRefresh">
                <IconifyIcon icon="lucide:refresh-cw" />
                刷新
              </Button>
              <div class="oa-lite-header-widget-bar">
                <ThemeToggle class="oa-lite-header-widget" />
                <LanguageToggle class="oa-lite-header-widget" />
                <VbenFullScreen class="oa-lite-header-widget" />
                <TimezoneButton class="oa-lite-header-widget" />
                <Notification
                  class="oa-lite-header-widget"
                  :dot="showNotificationDot"
                  :notifications="headerNotifications"
                  @clear="handleNotificationClear"
                  @make-all="handleNotificationMakeAll"
                  @open="handleNotificationOpen"
                  @read="handleNotificationRead"
                  @view-all="handleNotificationViewAll"
                />
                <UserDropdown
                  :avatar="avatar"
                  :description="userStore.userInfo?.email"
                  :menus="headerMenus"
                  :tag-text="userStore.userInfo?.username"
                  :text="userStore.userInfo?.nickname"
                  class="oa-lite-header-user"
                  @logout="handleLogout"
                />
              </div>
            </div>
          </div>
        </header>

        <main class="oa-lite-main">
          <div class="oa-lite-home-shell">
            <template v-if="viewState === 'profile'">
              <section class="oa-lite-profile-shell">
                <div class="oa-lite-profile-header">
                  <div>
                    <div class="oa-lite-section-title">个人中心</div>
                    <div class="oa-lite-section-desc">
                      当前账号资料、基础信息、密码设置和社交绑定
                    </div>
                  </div>
                </div>
                <div class="oa-lite-profile-content">
                  <ProfileCenter />
                </div>
              </section>
            </template>

            <template v-else-if="activeTab === 'create'">
              <section class="oa-lite-stat-pillar">
                <button
                  v-for="item in dashboardNavItems"
                  :key="item.key"
                  class="oa-lite-stat-item"
                  @click="openTab(item.key)"
                >
                  <span class="oa-lite-stat-count">{{ item.count }}</span>
                  <IconifyIcon :icon="item.icon" class="oa-lite-stat-icon" />
                  <span class="oa-lite-stat-label">{{ item.label }}</span>
                  <IconifyIcon icon="lucide:chevron-right" class="oa-lite-stat-arrow" />
                </button>
              </section>

              <section class="oa-lite-create-shell">
                <div class="oa-lite-create-toolbar">
                  <div v-if="createCategoryTabs.length > 0" class="oa-lite-category-tabs">
                    <button
                      v-for="item in createCategoryTabs"
                      :key="item.code"
                      class="oa-lite-category-tab"
                      :class="{ active: currentCreateCategoryCode === item.code }"
                      @click="selectCreateCategory(item.code)"
                    >
                      {{ item.name }}
                    </button>
                  </div>
                </div>

                <div class="oa-lite-template-section">
                  <div class="oa-lite-template-section-head">
                    <span class="oa-lite-template-section-title">
                      {{ currentCreateCategoryName }}
                    </span>
                    <IconifyIcon icon="lucide:chevron-right" class="oa-lite-template-section-arrow" />
                  </div>

                  <div v-if="showLeaveCreateCard" class="oa-lite-template-grid">
                    <button
                      class="oa-lite-template-card"
                      :disabled="leavePublishing"
                      @click="openLeaveForm()"
                    >
                      <div class="oa-lite-template-icon">
                        <IconifyIcon icon="lucide:file-heart" />
                      </div>
                      <div class="oa-lite-template-body">
                        <div class="oa-lite-template-name">请假</div>
                        <div class="oa-lite-template-desc">
                          发起真实请假审批流程
                        </div>
                      </div>
                    </button>
                  </div>
                  <Empty
                    v-else
                    description="当前分类暂无可发起流程"
                    :image-style="{ height: '80px' }"
                  />
                </div>
              </section>
            </template>

            <template v-else>
              <section class="oa-lite-center-shell">
                <aside class="oa-lite-center-nav">
                  <button
                    v-for="item in dashboardNavItems"
                    :key="item.key"
                    class="oa-lite-center-nav-item"
                    :class="{ active: activeTab === item.key }"
                    @click="openTab(item.key)"
                  >
                    <span class="oa-lite-center-nav-main">
                      <span class="oa-lite-center-nav-icon">
                        <IconifyIcon :icon="item.icon" />
                      </span>
                      <span class="oa-lite-center-nav-text">{{ item.label }}</span>
                    </span>
                    <Tag class="oa-lite-center-nav-count">{{ item.count }}</Tag>
                  </button>
                </aside>

                <div class="oa-lite-center-content">
                  <div class="oa-lite-list-panel">
                    <div class="oa-lite-section-header oa-lite-list-header">
                      <div>
                        <div class="oa-lite-section-title">{{ currentListTitle }}</div>
                        <div class="oa-lite-section-desc">{{ currentListSubtitle }}</div>
                      </div>
                      <Button type="link" @click="resetCurrentFilter">重置筛选</Button>
                    </div>

                    <div class="oa-lite-filters">
                      <Input
                        v-model:value="currentFilter!.name"
                        :placeholder="getKeywordPlaceholder()"
                        allow-clear
                        @press-enter="handleFilterSubmit"
                      >
                        <template #prefix>
                          <IconifyIcon icon="lucide:search" />
                        </template>
                      </Input>

                      <Select
                        v-if="showProcessFilter"
                        v-model:value="currentProcessFilterValue"
                        class="oa-lite-filter-control"
                        placeholder="所属流程"
                        allow-clear
                        :options="currentProcessOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <Select
                        v-if="showCategoryFilter"
                        v-model:value="currentFilter!.category"
                        class="oa-lite-filter-control"
                        placeholder="流程分类"
                        allow-clear
                        :options="categoryOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <Select
                        v-if="showStatusFilter"
                        v-model:value="currentFilter!.status"
                        class="oa-lite-filter-control"
                        :placeholder="activeTab === 'processed' ? '审批状态' : '流程状态'"
                        allow-clear
                        :options="currentStatusOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <DatePicker.RangePicker
                        v-model:value="currentFilter!.createTime"
                        class="oa-lite-filter-range"
                        show-time
                        value-format="YYYY-MM-DD HH:mm:ss"
                        format="YYYY-MM-DD HH:mm:ss"
                        :placeholder="getCreateTimePlaceholder()"
                      />
                    </div>

                    <div class="oa-lite-filter-actions">
                      <Button type="primary" @click="handleFilterSubmit">查询</Button>
                      <Button class="oa-lite-white-button" @click="resetCurrentFilter">
                        重置
                      </Button>
                    </div>

                    <Spin :spinning="currentListLoading">
                      <div v-if="currentList.length > 0" class="oa-lite-list">
                        <button
                          v-for="item in currentList"
                          :key="getItemIdentity(item)"
                          class="oa-lite-list-item"
                          :class="{ active: selectedItem === item }"
                          @click="selectedItem = item"
                        >
                          <div class="oa-lite-list-head">
                            <div class="oa-lite-list-title">{{ getItemTitle(item) }}</div>
                            <span class="oa-lite-list-date">{{ getItemMetaRight(item) }}</span>
                          </div>
                          <div class="oa-lite-list-summary">{{ getItemSummary(item) }}</div>
                          <div class="oa-lite-list-meta">
                            <span>{{ getItemMetaLeft(item) }}</span>
                            <Tag
                              v-if="getItemStatus(item) !== undefined"
                              class="oa-lite-list-status-tag"
                            >
                              {{ getItemStatusText(item) }}
                            </Tag>
                          </div>
                          <div class="oa-lite-list-extra">
                            <span
                              v-for="row in getExtraMetaRows(item)"
                              :key="`${getItemTitle(item)}-${row}`"
                            >
                              {{ row }}
                            </span>
                          </div>
                        </button>
                      </div>
                      <Empty v-else :description="`暂无${currentListTitle}数据`" />
                    </Spin>

                    <div
                      v-if="currentPageState && currentPageState.total > 0"
                      class="oa-lite-pagination-wrap"
                    >
                      <Pagination
                        :current="currentPageState.pageNo"
                        :page-size="currentPageState.pageSize"
                        :total="currentPageState.total"
                        :show-size-changer="true"
                        :show-total="(total) => `共 ${total} 条`"
                        @change="handlePageChange"
                      />
                    </div>
                  </div>

                  <div class="oa-lite-detail-panel">
                    <ProcessDetail
                      v-if="currentDetailRequest"
                      :request="currentDetailRequest"
                      :section="currentDetailSection"
                      @refresh="handleDetailRefresh"
                      @recreate="openLeaveForm"
                    />
                    <div v-else class="oa-lite-detail-empty">
                      <Empty :description="`请选择${currentListTitle}查看详情`" />
                    </div>
                  </div>
                </div>
              </section>
            </template>
          </div>
        </main>
      </template>
    </div>
  </ConfigProvider>
</template>

<style lang="scss" scoped>
.oa-lite-page {
  min-height: 100vh;
  background: #f7f8fa;
  color: #111827;
  position: relative;
}

.oa-lite-page :deep(.bg-card),
.oa-lite-page :deep(.bg-background),
.oa-lite-page :deep(.bg-popover) {
  background: #fff !important;
}

.oa-lite-page :deep(.bg-background-deep) {
  background: #f7f8fa !important;
}

.oa-lite-page :deep(.bg-accent),
.oa-lite-page :deep(.bg-muted),
.oa-lite-page :deep(.bg-secondary),
.oa-lite-page :deep(.bg-gray-100),
.oa-lite-page :deep(.dark\:bg-gray-600) {
  background: #f8fafc !important;
}

.oa-lite-page :deep(.border-border) {
  border-color: #dbe5f0 !important;
}

.oa-lite-page :deep(.text-foreground),
.oa-lite-page :deep(.text-card-foreground),
.oa-lite-page :deep(.text-popover-foreground),
.oa-lite-page :deep(.text-accent-foreground) {
  color: #111827 !important;
}

.oa-lite-page :deep(.text-muted-foreground),
.oa-lite-page :deep(.text-gray-500),
.oa-lite-page :deep([class~='text-foreground/80']),
.oa-lite-page :deep([class~='text-foreground/60']) {
  color: #64748b !important;
}

.oa-lite-page :deep(.ant-empty-description),
.oa-lite-page :deep(.ant-spin-text),
.oa-lite-page :deep(.ant-pagination-total-text),
.oa-lite-page :deep(.ant-pagination .ant-pagination-item a),
.oa-lite-page :deep(.ant-select-selection-item),
.oa-lite-page :deep(.ant-select-selection-search-input),
.oa-lite-page :deep(.ant-picker-input > input),
.oa-lite-page :deep(.ant-form-item-label > label),
.oa-lite-page :deep(.ant-alert-message),
.oa-lite-page :deep(.ant-alert-description),
.oa-lite-page :deep(.ant-input-prefix),
.oa-lite-page :deep(.ant-input-show-count-suffix),
.oa-lite-page :deep(.ant-picker-suffix),
.oa-lite-page :deep(.ant-picker-clear),
.oa-lite-page :deep(.ant-select-arrow),
.oa-lite-page :deep(.ant-select-clear) {
  color: #111827 !important;
}

.oa-lite-page :deep(.ant-form-item-extra),
.oa-lite-page :deep(.ant-form-item-explain),
.oa-lite-page :deep(.ant-pagination-options),
.oa-lite-page :deep(.ant-empty-normal) {
  color: #64748b !important;
}

.oa-lite-page :deep(.ant-btn:not(.ant-btn-primary):not(.ant-btn-dangerous)),
.oa-lite-page :deep(.ant-btn:not(.ant-btn-primary):not(.ant-btn-dangerous) > span),
.oa-lite-page :deep(.ant-btn-link),
.oa-lite-page :deep(.ant-btn-link > span) {
  color: #111827 !important;
}

.oa-lite-bg {
  position: fixed;
  inset: 0 auto auto 0;
  width: 100%;
  height: 420px;
  background:
    radial-gradient(circle at 20% 10%, rgb(221 234 255 / 90%), transparent 38%),
    linear-gradient(180deg, rgb(238 244 255 / 85%) 0%, rgb(247 248 250 / 0%) 100%);
  pointer-events: none;
  z-index: 0;
  opacity: 0.6;
}

.oa-lite-topbar,
.oa-lite-main,
.oa-lite-leave-page {
  position: relative;
  z-index: 1;
}

.oa-lite-topbar {
  padding: 20px 24px 0;
}

.oa-lite-topbar-inner {
  max-width: 1260px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 24px;
}

.oa-lite-brand {
  display: flex;
  align-items: center;
  gap: 14px;
}

.oa-lite-brand-icon {
  width: 42px;
  height: 42px;
  border-radius: 14px;
  background: linear-gradient(135deg, #ff9a3d 0%, #ff6a00 100%);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  box-shadow: 0 8px 20px rgb(255 106 0 / 28%);
}

.oa-lite-brand-title {
  font-size: 20px;
  font-weight: 700;
}

.oa-lite-brand-subtitle {
  margin-top: 4px;
  color: #64748b;
  font-size: 13px;
}

.oa-lite-topnav {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 34px;
}

.oa-lite-topnav-tab {
  position: relative;
  border: none;
  background: transparent;
  padding: 8px 2px 10px;
  color: #6b7280;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  transition: color 0.18s ease;
}

.oa-lite-topnav-tab:hover,
.oa-lite-topnav-tab.active {
  color: #111827;
}

.oa-lite-topnav-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  width: 20px;
  height: 3px;
  transform: translateX(-50%);
  border-radius: 999px;
  background: #111827;
}

.oa-lite-user-actions {
  display: flex;
  align-items: center;
  gap: 12px;
  justify-content: flex-end;
  flex-wrap: wrap;
}

.oa-lite-refresh-button {
  white-space: nowrap;
}

.oa-lite-header-widget-bar {
  display: flex;
  align-items: center;
  padding: 4px 8px 4px 10px;
  border: 1px solid #e7edf4;
  border-radius: 999px;
  background: rgb(255 255 255 / 92%);
  box-shadow: 0 10px 24px rgb(15 23 42 / 6%);
  backdrop-filter: blur(14px);
}

.oa-lite-header-widget-bar :deep(.text-foreground),
.oa-lite-header-widget-bar :deep(.text-muted-foreground),
.oa-lite-header-widget-bar :deep(.anticon),
.oa-lite-header-widget-bar :deep(svg) {
  color: #111827 !important;
}

.oa-lite-header-widget-bar :deep(.mr-1),
.oa-lite-header-widget-bar :deep(.mr-2) {
  margin-right: 4px !important;
}

.oa-lite-header-widget-bar :deep(.ml-1) {
  margin-left: 0 !important;
}

.oa-lite-header-widget-bar :deep(.hover\:bg-accent:hover),
.oa-lite-header-widget-bar :deep(.hover\:text-accent-foreground:hover) {
  color: #111827 !important;
}

.oa-lite-header-user :deep(.mr-2) {
  margin-right: 0 !important;
}

.oa-lite-main {
  padding: 18px 24px 32px;
}

.oa-lite-home-shell {
  max-width: 1260px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 22px;
}

.oa-lite-stat-pillar {
  align-self: center;
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  justify-content: center;
  overflow: hidden;
  border: 1px solid #eef2f7;
  border-radius: 999px;
  background: rgb(255 255 255 / 94%);
  box-shadow: 0 10px 30px rgb(15 23 42 / 6%);
  backdrop-filter: blur(14px);
}

.oa-lite-stat-item {
  border: none;
  background: transparent;
  padding: 12px 20px;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: #475569;
  cursor: pointer;
  transition:
    background-color 0.18s ease,
    color 0.18s ease;
}

.oa-lite-stat-item + .oa-lite-stat-item {
  border-left: 1px solid #edf2f7;
}

.oa-lite-stat-item:hover {
  background: #f8fbff;
  color: #2563eb;
}

.oa-lite-stat-count {
  min-width: 28px;
  height: 28px;
  padding: 0 8px;
  border-radius: 999px;
  background: #f3f4f6;
  color: #111827;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 700;
}

.oa-lite-stat-item:hover .oa-lite-stat-count {
  background: #eff6ff;
  color: #2563eb;
}

.oa-lite-stat-icon,
.oa-lite-stat-arrow {
  color: #94a3b8;
  font-size: 15px;
}

.oa-lite-stat-label {
  font-size: 14px;
  font-weight: 500;
}

.oa-lite-create-shell {
  width: 100%;
  max-width: 1000px;
  margin: 0 auto;
}

.oa-lite-profile-shell {
  width: 100%;
  max-width: 1260px;
}

.oa-lite-profile-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
}

.oa-lite-profile-content {
  border: 1px solid #e7edf4;
  border-radius: 24px;
  background: rgb(255 255 255 / 92%);
  box-shadow: 0 12px 34px rgb(15 23 42 / 5%);
  padding: 22px;
}

.oa-lite-profile-content :deep(.ant-card) {
  border-color: #e7edf4 !important;
  border-radius: 20px !important;
  box-shadow: none !important;
}

.oa-lite-profile-content :deep(.ant-card-head) {
  border-bottom-color: #edf2f7 !important;
}

.oa-lite-profile-content :deep(.ant-tabs-nav::before) {
  border-bottom-color: #edf2f7 !important;
}

.oa-lite-create-toolbar {
  position: sticky;
  top: 0;
  z-index: 3;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  gap: 16px;
  padding: 8px 0 20px;
  background: rgb(247 248 250 / 88%);
  backdrop-filter: blur(14px);
}

.oa-lite-category-tabs {
  display: flex;
  align-items: center;
  gap: 30px;
  overflow-x: auto;
  scrollbar-width: none;
}

.oa-lite-category-tabs::-webkit-scrollbar {
  display: none;
}

.oa-lite-category-tab {
  position: relative;
  border: none;
  background: transparent;
  padding: 0 0 12px;
  color: #6b7280;
  font-size: 15px;
  font-weight: 600;
  white-space: nowrap;
  cursor: pointer;
  transition: color 0.18s ease;
}

.oa-lite-category-tab:hover,
.oa-lite-category-tab.active {
  color: #111827;
}

.oa-lite-category-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  transform: translateX(-50%);
  width: 18px;
  height: 3px;
  border-radius: 999px;
  background: #111827;
}

.oa-lite-template-section {
  padding-top: 6px;
}

.oa-lite-template-section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 14px;
}

.oa-lite-template-section-title {
  font-size: 14px;
  color: #6b7280;
  font-weight: 600;
}

.oa-lite-template-section-arrow {
  color: #cbd5e1;
  font-size: 16px;
}

.oa-lite-template-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 16px;
}

.oa-lite-template-card {
  min-height: 82px;
  border: 1px solid transparent;
  background: #fff;
  border-radius: 20px;
  padding: 18px;
  display: flex;
  align-items: center;
  gap: 14px;
  text-align: left;
  cursor: pointer;
  box-shadow: 0 1px 8px rgb(0 0 0 / 4%);
  transition:
    transform 0.18s ease,
    border-color 0.18s ease,
    box-shadow 0.18s ease;
}

.oa-lite-template-card:hover {
  transform: translateY(-1px);
  border-color: #dbeafe;
  box-shadow: 0 10px 24px rgb(59 130 246 / 10%);
}

.oa-lite-template-card:disabled {
  cursor: wait;
  opacity: 0.82;
}

.oa-lite-template-icon {
  width: 44px;
  height: 44px;
  border-radius: 14px;
  background: linear-gradient(135deg, #60a5fa 0%, #2563eb 100%);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  flex-shrink: 0;
}

.oa-lite-template-body {
  min-width: 0;
}

.oa-lite-template-name {
  font-size: 15px;
  font-weight: 600;
  color: #191919;
}

.oa-lite-template-desc {
  margin-top: 4px;
  font-size: 12px;
  color: #94a3b8;
  line-height: 1.5;
}

.oa-lite-center-shell {
  display: grid;
  grid-template-columns: 180px minmax(0, 1fr);
  gap: 18px;
  align-items: start;
}

.oa-lite-center-nav {
  padding: 12px 0;
}

.oa-lite-center-nav-item {
  width: calc(100% - 8px);
  margin: 0 4px 8px;
  border: none;
  border-radius: 16px;
  background: transparent;
  padding: 12px 14px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  color: #64748b;
  cursor: pointer;
  transition:
    background-color 0.18s ease,
    box-shadow 0.18s ease,
    color 0.18s ease;
}

.oa-lite-center-nav-item:hover {
  background: rgb(15 23 42 / 4%);
  color: #111827;
}

.oa-lite-center-nav-item.active {
  background: #fff;
  color: #111827;
  box-shadow: 0 4px 14px rgb(15 23 42 / 6%);
}

.oa-lite-center-nav-main {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.oa-lite-center-nav-icon {
  font-size: 16px;
  color: inherit;
  display: inline-flex;
  align-items: center;
}

.oa-lite-center-nav-text {
  font-size: 14px;
  font-weight: 500;
  white-space: nowrap;
}

.oa-lite-center-nav-count.ant-tag {
  min-width: 28px;
  height: 24px;
  padding: 0 8px;
  margin-inline-end: 0;
  border-radius: 999px;
  border: 1px solid #e5e7eb;
  background: #fff !important;
  color: #334155 !important;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-center-content {
  display: grid;
  grid-template-columns: 340px minmax(0, 1fr);
  gap: 18px;
}

.oa-lite-list-panel,
.oa-lite-detail-panel {
  background: #fff;
  border: 1px solid #e7edf4;
  border-radius: 22px;
  box-shadow: 0 1px 10px rgb(0 0 0 / 4%);
  min-width: 0;
}

.oa-lite-list-panel {
  padding: 18px;
}

.oa-lite-detail-panel {
  padding: 18px;
  min-height: 680px;
}

.oa-lite-section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
}

.oa-lite-list-header {
  margin-bottom: 16px;
}

.oa-lite-section-title {
  font-size: 20px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-section-desc {
  margin-top: 6px;
  color: #64748b;
  font-size: 13px;
  line-height: 1.6;
}

.oa-lite-filters {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
  margin-bottom: 14px;
}

.oa-lite-filter-control,
.oa-lite-filter-range {
  width: 100%;
}

.oa-lite-filter-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-bottom: 18px;
}

.oa-lite-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.oa-lite-list-item {
  width: 100%;
  border: 1px solid #edf2f7;
  background: #fff;
  border-radius: 16px;
  text-align: left;
  padding: 14px;
  cursor: pointer;
  transition:
    transform 0.18s ease,
    border-color 0.18s ease,
    box-shadow 0.18s ease,
    background-color 0.18s ease;
}

.oa-lite-list-item:hover {
  transform: translateY(-1px);
  border-color: #dbe5f0;
}

.oa-lite-list-item.active {
  border-color: #bfdbfe;
  box-shadow: 0 10px 24px rgb(37 99 235 / 8%);
  background: #f8fbff;
}

.oa-lite-list-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.oa-lite-list-title {
  font-size: 15px;
  font-weight: 600;
  color: #111827;
}

.oa-lite-list-date {
  font-size: 12px;
  color: #94a3b8;
  white-space: nowrap;
}

.oa-lite-list-summary {
  margin-top: 10px;
  font-size: 13px;
  line-height: 1.65;
  color: #475569;
}

.oa-lite-list-meta {
  margin-top: 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  color: #334155;
  font-size: 13px;
}

.oa-lite-list-status-tag.ant-tag {
  margin-inline-end: 0;
  border-radius: 999px;
  border: 1px solid #dbe5f0;
  background: #fff !important;
  color: #111827 !important;
}

.oa-lite-list-extra {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  color: #64748b;
  font-size: 12px;
}

.oa-lite-pagination-wrap {
  margin-top: 18px;
  display: flex;
  justify-content: flex-end;
}

.oa-lite-detail-empty {
  min-height: 580px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-white-button {
  height: 36px;
  padding: 0 16px;
  border-radius: 999px;
  background: #fff;
  border: 1px solid #dbe5f0;
  color: #111827;
  box-shadow: none;
}

.oa-lite-leave-page {
  min-height: 100vh;
  background: #f4f5f7;
  display: flex;
  flex-direction: column;
}

.oa-lite-leave-header {
  height: 56px;
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
  display: flex;
  align-items: center;
  padding: 0 16px;
  position: sticky;
  top: 0;
  z-index: 20;
}

.oa-lite-leave-left {
  display: flex;
  align-items: center;
  gap: 24px;
}

.oa-lite-leave-back {
  width: 32px;
  height: 32px;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: #4b5563;
  cursor: pointer;
}

.oa-lite-leave-header-tabs {
  display: flex;
  align-items: center;
  gap: 24px;
  height: 100%;
}

.oa-lite-leave-header-tab {
  height: 56px;
  display: flex;
  align-items: center;
  font-size: 15px;
  color: #111827;
  font-weight: 600;
  position: relative;
}

.oa-lite-leave-header-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  transform: translateX(-50%);
  width: 24px;
  height: 3px;
  border-radius: 999px;
  background: #111827;
}

.oa-lite-leave-main {
  flex: 1;
  overflow-y: auto;
  padding: 24px 0 80px;
}

.oa-lite-leave-shell {
  max-width: 800px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.oa-lite-leave-card {
  background: #fff;
  border-radius: 16px;
  border: 1px solid #eef1f4;
  box-shadow: 0 1px 8px rgb(0 0 0 / 4%);
  padding: 32px;
}

.oa-lite-leave-title-row {
  position: relative;
}

.oa-lite-leave-title {
  margin: 0;
  font-size: 30px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-leave-subtitle {
  margin: 6px 0 0;
  font-size: 13px;
  color: #9ca3af;
}

.oa-lite-leave-qr {
  position: absolute;
  top: 0;
  right: 0;
  font-size: 32px;
  color: #d1d5db;
}

.oa-lite-leave-divider {
  border-bottom: 1px dashed #e5e7eb;
  padding-top: 14px;
  margin-bottom: 12px;
}

.oa-lite-leave-card :deep(.ant-form-item-label > label) {
  color: #374151;
  font-size: 13px;
}

.oa-lite-leave-card :deep(.ant-input),
.oa-lite-leave-card :deep(.ant-input-affix-wrapper),
.oa-lite-leave-card :deep(.ant-picker),
.oa-lite-leave-card :deep(.ant-select-selector),
.oa-lite-leave-card :deep(textarea.ant-input),
.oa-lite-list-panel :deep(.ant-input),
.oa-lite-list-panel :deep(.ant-input-affix-wrapper),
.oa-lite-list-panel :deep(.ant-picker),
.oa-lite-list-panel :deep(.ant-select-selector),
.oa-lite-list-panel :deep(textarea.ant-input),
.oa-lite-detail-panel :deep(.ant-input),
.oa-lite-detail-panel :deep(.ant-input-affix-wrapper),
.oa-lite-detail-panel :deep(.ant-picker),
.oa-lite-detail-panel :deep(.ant-select-selector),
.oa-lite-detail-panel :deep(textarea.ant-input) {
  background: #fff !important;
  color: #111827 !important;
  border: 1px solid #d1d5db !important;
  box-shadow: none !important;
}

.oa-lite-leave-card :deep(.ant-input::placeholder),
.oa-lite-leave-card :deep(textarea.ant-input::placeholder),
.oa-lite-leave-card :deep(.ant-select-selection-placeholder),
.oa-lite-leave-card :deep(.ant-picker-input input::placeholder),
.oa-lite-list-panel :deep(.ant-input::placeholder),
.oa-lite-list-panel :deep(textarea.ant-input::placeholder),
.oa-lite-list-panel :deep(.ant-select-selection-placeholder),
.oa-lite-list-panel :deep(.ant-picker-input input::placeholder),
.oa-lite-detail-panel :deep(.ant-input::placeholder),
.oa-lite-detail-panel :deep(textarea.ant-input::placeholder),
.oa-lite-detail-panel :deep(.ant-select-selection-placeholder),
.oa-lite-detail-panel :deep(.ant-picker-input input::placeholder) {
  color: #9ca3af !important;
}

.oa-lite-leave-card :deep(.ant-picker-input > input),
.oa-lite-leave-card :deep(.ant-select-selection-item),
.oa-lite-leave-card :deep(.ant-select-arrow),
.oa-lite-leave-card :deep(.ant-picker-suffix),
.oa-lite-leave-card :deep(.ant-picker-clear),
.oa-lite-list-panel :deep(.ant-picker-input > input),
.oa-lite-list-panel :deep(.ant-select-selection-item),
.oa-lite-list-panel :deep(.ant-select-arrow),
.oa-lite-list-panel :deep(.ant-picker-suffix),
.oa-lite-list-panel :deep(.ant-picker-clear),
.oa-lite-detail-panel :deep(.ant-picker-input > input),
.oa-lite-detail-panel :deep(.ant-select-selection-item),
.oa-lite-detail-panel :deep(.ant-select-arrow),
.oa-lite-detail-panel :deep(.ant-picker-suffix),
.oa-lite-detail-panel :deep(.ant-picker-clear) {
  color: #111827 !important;
}

.oa-lite-leave-card :deep(.ant-input:focus),
.oa-lite-leave-card :deep(.ant-input-affix-wrapper-focused),
.oa-lite-leave-card :deep(.ant-picker-focused),
.oa-lite-leave-card :deep(.ant-select-focused .ant-select-selector),
.oa-lite-leave-card :deep(textarea.ant-input:focus),
.oa-lite-list-panel :deep(.ant-input:focus),
.oa-lite-list-panel :deep(.ant-input-affix-wrapper-focused),
.oa-lite-list-panel :deep(.ant-picker-focused),
.oa-lite-list-panel :deep(.ant-select-focused .ant-select-selector),
.oa-lite-list-panel :deep(textarea.ant-input:focus),
.oa-lite-detail-panel :deep(.ant-input:focus),
.oa-lite-detail-panel :deep(.ant-input-affix-wrapper-focused),
.oa-lite-detail-panel :deep(.ant-picker-focused),
.oa-lite-detail-panel :deep(.ant-select-focused .ant-select-selector),
.oa-lite-detail-panel :deep(textarea.ant-input:focus) {
  border-color: #3b82f6 !important;
  box-shadow: 0 0 0 1px rgb(59 130 246 / 18%) !important;
}

:deep(.oa-lite-select-popup.ant-select-dropdown),
:deep(.oa-lite-status-popup.ant-select-dropdown) {
  background: #fff !important;
  border: 1px solid #d1d5db !important;
  box-shadow: 0 8px 24px rgb(15 23 42 / 10%) !important;
  border-radius: 16px !important;
  padding: 8px 0 !important;
}

:deep(.oa-lite-select-popup .ant-select-item),
:deep(.oa-lite-status-popup .ant-select-item) {
  color: #111827 !important;
  background: #fff !important;
}

:deep(.oa-lite-select-popup .ant-select-item-option-active:not(.ant-select-item-option-disabled)),
:deep(.oa-lite-status-popup .ant-select-item-option-active:not(.ant-select-item-option-disabled)) {
  background: #f3f4f6 !important;
}

:deep(.oa-lite-select-popup .ant-select-item-option-selected:not(.ant-select-item-option-disabled)),
:deep(.oa-lite-status-popup .ant-select-item-option-selected:not(.ant-select-item-option-disabled)) {
  background: #eff6ff !important;
  color: #2563eb !important;
}

.oa-lite-leave-flow-head {
  display: flex;
  align-items: center;
  border-bottom: 1px solid #f1f5f9;
  padding-bottom: 16px;
}

.oa-lite-leave-flow-title {
  font-size: 15px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-leave-flow-tag {
  margin-left: 12px;
  font-size: 12px;
  color: #2563eb;
}

.oa-lite-leave-flow-body {
  position: relative;
  padding-top: 18px;
  padding-left: 18px;

  :deep(.ant-timeline) {
    margin: 0;
    padding-top: 0 !important;
  }

  :deep(.ant-timeline-item-content) {
    color: #111827;
  }

  :deep(.font-bold) {
    color: #111827;
    font-weight: 700;
  }

  :deep(.text-sm) {
    color: #334155;
  }

  :deep(.text-gray-500) {
    color: #64748b !important;
  }

  :deep(.bg-gray-100) {
    background: #f8fafc !important;
    color: #111827 !important;
  }

  :deep(.dark\:bg-gray-600) {
    background: #f8fafc !important;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary) {
    width: auto;
    min-width: 116px;
    height: 36px;
    padding: 0 14px;
    border-radius: 12px;
    border-color: #dbe5f0;
    background: #fff;
    color: #111827;
    box-shadow: none;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary::after) {
    content: '选择审批人';
    margin-left: 6px;
    font-size: 13px;
    font-weight: 600;
    color: #111827;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary:hover) {
    border-color: #bfdbfe;
    color: #2563eb;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary:hover::after) {
    color: #2563eb;
  }
}

.oa-lite-leave-flow-line {
  position: absolute;
  top: 26px;
  bottom: 34px;
  left: 21px;
  width: 1px;
  background: #d1d5db;
}

.oa-lite-leave-flow-node {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 22px;
  margin-bottom: 30px;
}

.oa-lite-leave-flow-node-last {
  margin-bottom: 0;
}

.oa-lite-leave-flow-dot {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  background: #d1d5db;
  box-shadow: 0 0 0 4px #fff;
  position: relative;
  left: -3px;
  z-index: 2;
  flex-shrink: 0;
  margin-top: 4px;
}

.oa-lite-leave-node-title {
  font-size: 13px;
  font-weight: 600;
  color: #1f2937;
}

.oa-lite-leave-node-subtitle {
  margin-top: 2px;
  font-size: 11px;
  color: #9ca3af;
}

.oa-lite-leave-node-body {
  min-width: 0;
}

.oa-lite-leave-node-select {
  width: 220px;
  margin-top: 12px;
}

.oa-lite-leave-submit-row {
  padding-top: 20px;
}

@media (max-width: 1000px) {
  .oa-lite-topbar-inner {
    grid-template-columns: auto minmax(0, 1fr);
  }

  .oa-lite-user-actions {
    grid-column: 1 / -1;
    justify-content: flex-start;
  }

  .oa-lite-template-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 1024px) {
  .oa-lite-topbar-inner {
    grid-template-columns: 1fr;
    justify-items: start;
  }

  .oa-lite-topnav {
    justify-content: flex-start;
  }

  .oa-lite-center-shell,
  .oa-lite-center-content {
    grid-template-columns: 1fr;
  }

  .oa-lite-center-nav {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
    padding: 0;
  }

  .oa-lite-center-nav-item {
    width: 100%;
    margin: 0;
  }

  .oa-lite-template-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 768px) {
  .oa-lite-topbar {
    padding: 16px 14px 0;
  }

  .oa-lite-main {
    padding: 14px 14px 20px;
  }

  .oa-lite-stat-pillar {
    width: 100%;
    flex-wrap: nowrap;
    justify-content: flex-start;
    overflow-x: auto;
  }

  .oa-lite-stat-item {
    flex: 0 0 auto;
  }

  .oa-lite-center-nav {
    grid-template-columns: 1fr;
  }

  .oa-lite-create-search {
    display: none;
  }

  .oa-lite-list-panel,
  .oa-lite-detail-panel {
    padding: 16px;
    border-radius: 18px;
  }

  .oa-lite-template-grid {
    grid-template-columns: 1fr;
  }

  .oa-lite-section-header {
    flex-direction: column;
    align-items: flex-start;
  }

  .oa-lite-leave-shell {
    padding: 0 14px;
  }

  .oa-lite-leave-card {
    padding: 20px;
  }
}
</style>

<style lang="scss">
body.oa-lite-light-theme {
  --background: 0 0% 100%;
  --background-deep: 216 20.11% 95.47%;
  --foreground: 210 6% 21%;
  --muted: 240 4.8% 95.9%;
  --muted-foreground: 240 3.8% 46.1%;
  --accent: 240 5% 96%;
  --accent-hover: 200deg 10% 90%;
  --accent-foreground: 240 6% 10%;
  --border: 240 5.9% 90%;
}

body.oa-lite-light-theme .z-popup,
body.oa-lite-light-theme [role='dialog'],
body.oa-lite-light-theme [role='menu'] {
  background: #fff !important;
  border-color: #dbe5f0 !important;
  color: #111827 !important;
  box-shadow: 0 18px 40px rgb(15 23 42 / 12%) !important;
}

body.oa-lite-light-theme .z-popup .bg-popover,
body.oa-lite-light-theme .z-popup .bg-background,
body.oa-lite-light-theme .z-popup .bg-card,
body.oa-lite-light-theme .z-popup .text-popover-foreground,
body.oa-lite-light-theme .z-popup .text-foreground,
body.oa-lite-light-theme .z-popup .text-card-foreground,
body.oa-lite-light-theme .z-popup .text-muted-foreground,
body.oa-lite-light-theme [role='dialog'] .bg-popover,
body.oa-lite-light-theme [role='dialog'] .bg-background,
body.oa-lite-light-theme [role='dialog'] .bg-card,
body.oa-lite-light-theme [role='menu'] .bg-popover,
body.oa-lite-light-theme [role='menu'] .bg-background,
body.oa-lite-light-theme [role='menu'] .bg-card {
  background: #fff !important;
  color: #111827 !important;
}

body.oa-lite-light-theme .z-popup .text-muted-foreground,
body.oa-lite-light-theme [role='dialog'] .text-muted-foreground,
body.oa-lite-light-theme [role='menu'] .text-muted-foreground {
  color: #64748b !important;
}

body.oa-lite-light-theme .z-popup .border-border,
body.oa-lite-light-theme [role='dialog'] .border-border,
body.oa-lite-light-theme [role='menu'] .border-border {
  border-color: #e5e7eb !important;
}

body.oa-lite-light-theme .z-popup [data-highlighted],
body.oa-lite-light-theme .z-popup .hover\:bg-accent:hover,
body.oa-lite-light-theme [role='menu'] [data-highlighted],
body.oa-lite-light-theme [role='menu'] .hover\:bg-accent:hover,
body.oa-lite-light-theme [role='dialog'] .hover\:bg-accent:hover {
  background: #f3f4f6 !important;
  color: #111827 !important;
}

body.oa-lite-light-theme .z-popup button,
body.oa-lite-light-theme .z-popup svg,
body.oa-lite-light-theme .z-popup .anticon,
body.oa-lite-light-theme [role='dialog'] button,
body.oa-lite-light-theme [role='dialog'] svg,
body.oa-lite-light-theme [role='menu'] button,
body.oa-lite-light-theme [role='menu'] svg {
  color: #111827 !important;
}
</style>
