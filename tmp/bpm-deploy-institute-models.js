#!/usr/bin/env node

const { randomUUID } = require('node:crypto');

const BASE_URL = 'http://127.0.0.1:48080/admin-api';
const TENANT_ID = '1';
const USERNAME = 'admin';
const PASSWORD = 'admin123';
const APPROVAL_FORM_ID = 40;

const EXISTING_MODEL_KEYS = [
  'oa_leave',
  'oa_trip',
  'oa_seal',
  'oa_document',
  'oa_project',
  'oa_staffing',
  'oa_overtime',
  'oa_attendance',
  'oa_expense',
  'w123',
];

const NEW_MODELS = [
  {
    key: 'oa_leave_cancel',
    name: '销假流程',
    formCustomCreatePath: '/bpm/oa/leave-cancel/create',
    formCustomViewPath: '/bpm/oa/leave-cancel/detail',
  },
  {
    key: 'oa_outing',
    name: '临时外出流程',
    formCustomCreatePath: '/bpm/oa/outing/create',
    formCustomViewPath: '/bpm/oa/outing/detail',
  },
];

const USER_IDS = {
  yuanZhang: 215,
  zhangHua: 219,
  zhangLing: 220,
  yanJi: 226,
  heZhiHua: 227,
  liHaoJie: 228,
  zhuXinJie: 229,
  laiZhiYong: 230,
};

function deepClone(value) {
  return value == null ? value : JSON.parse(JSON.stringify(value));
}

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function log(message, payload) {
  if (payload === undefined) {
    console.log(message);
    return;
  }
  console.log(message, JSON.stringify(payload, null, 2));
}

async function request(method, path, body, token) {
  const headers = {
    'tenant-id': TENANT_ID,
  };
  if (token) {
    headers.Authorization = `Bearer ${token}`;
  }
  if (body !== undefined) {
    headers['Content-Type'] = 'application/json';
  }
  const response = await fetch(`${BASE_URL}${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const text = await response.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch (error) {
    throw new Error(`接口 ${method} ${path} 返回非 JSON: ${text}`);
  }
  if (!response.ok) {
    throw new Error(`接口 ${method} ${path} HTTP ${response.status}: ${text}`);
  }
  if (json.code !== 0) {
    throw new Error(`接口 ${method} ${path} 业务失败: ${text}`);
  }
  return json.data;
}

async function login() {
  const data = await request('POST', '/system/auth/login', {
    username: USERNAME,
    password: PASSWORD,
  });
  assert(data?.accessToken, '登录成功但未返回 accessToken');
  return data.accessToken;
}

function buildConditionRule(rightSide) {
  return {
    and: true,
    rules: [
      {
        opCode: '==',
        leftSide: 'PROCESS_START_USER_ID',
        rightSide: String(rightSide),
      },
    ],
  };
}

function buildConditionSettingByUsers(userIds) {
  return {
    defaultFlow: false,
    conditionType: 2,
    conditionGroups: {
      and: false,
      conditions: userIds.map((userId) => buildConditionRule(userId)),
    },
  };
}

function buildDefaultConditionSetting() {
  return {
    defaultFlow: true,
  };
}

function buildApproveNode(template, options) {
  const node = deepClone(template);
  node.id = options.id;
  node.type = 11;
  node.name = options.name;
  node.showText = options.showText;
  node.candidateStrategy = options.candidateStrategy;
  node.candidateParam = options.candidateParam;
  node.childNode = options.childNode;
  node.assignStartUserHandlerType = 2;
  delete node.conditionNodes;
  delete node.conditionSetting;
  return node;
}

function buildUserApprove(template, userId, name, childNode) {
  return buildApproveNode(template, {
    id: `Activity_${randomUUID().replace(/-/g, '')}`,
    name,
    showText: `指定成员：${name.replace('审批', '')}`,
    candidateStrategy: 30,
    candidateParam: String(userId),
    childNode,
  });
}

function buildDeptLeaderApprove(template, childNode) {
  return buildApproveNode(template, {
    id: `Activity_${randomUUID().replace(/-/g, '')}`,
    name: '部门负责人审批',
    showText: '发起人部门负责人',
    candidateStrategy: 37,
    candidateParam: '1',
    childNode,
  });
}

function buildStartUserSelectApprove(template, childNode) {
  return buildApproveNode(template, {
    id: `Activity_${randomUUID().replace(/-/g, '')}`,
    name: '严己白自选审批人',
    showText: '发起人自选（张华/张龄/朱新捷三选一）',
    candidateStrategy: 35,
    candidateParam: '',
    childNode,
  });
}

function buildConditionNode(name, showText, conditionSetting, childNode) {
  return {
    id: `Flow_${randomUUID().replace(/-/g, '')}`,
    type: 50,
    name,
    showText,
    childNode,
    conditionSetting,
  };
}

function findFirstApproveNode(node) {
  if (!node) {
    return null;
  }
  if (node.type === 11) {
    return node;
  }
  if (Array.isArray(node.conditionNodes)) {
    for (const conditionNode of node.conditionNodes) {
      const matched = findFirstApproveNode(conditionNode.childNode);
      if (matched) {
        return matched;
      }
    }
  }
  return findFirstApproveNode(node.childNode);
}

function buildSpecialSimpleModel(baseStartNode, approveTemplate) {
  const endNode = {
    id: 'EndEvent',
    type: 1,
    name: '结束',
  };

  const presidentOnly = () =>
    buildUserApprove(approveTemplate, USER_IDS.yuanZhang, '院长审批', undefined);

  const startNode = deepClone(baseStartNode);
  startNode.childNode = {
    id: `GateWay_${randomUUID().replace(/-/g, '')}`,
    type: 51,
    name: '院所审批分流',
    showText: '已配置特殊人员审批分支',
    childNode: endNode,
    conditionNodes: [
      buildConditionNode(
        '张华张龄朱新捷直达院长',
        '张华/张龄/朱新捷发起时直达院长',
        buildConditionSettingByUsers([
          USER_IDS.zhangHua,
          USER_IDS.zhangLing,
          USER_IDS.zhuXinJie,
        ]),
        presidentOnly(),
      ),
      buildConditionNode(
        '严己白三选一后院长',
        '严己白先从张华/张龄/朱新捷中自选一人，再到院长',
        buildConditionSettingByUsers([USER_IDS.yanJi]),
        buildStartUserSelectApprove(approveTemplate, presidentOnly()),
      ),
      buildConditionNode(
        '赖志勇先朱新捷后院长',
        '赖志勇先朱新捷审批，再到院长',
        buildConditionSettingByUsers([USER_IDS.laiZhiYong]),
        buildUserApprove(
          approveTemplate,
          USER_IDS.zhuXinJie,
          '朱新捷审批',
          presidentOnly(),
        ),
      ),
      buildConditionNode(
        '李豪杰先何志华张华后院长',
        '李豪杰先何志华，再张华，最后院长',
        buildConditionSettingByUsers([USER_IDS.liHaoJie]),
        buildUserApprove(
          approveTemplate,
          USER_IDS.heZhiHua,
          '何志华审批',
          buildUserApprove(
            approveTemplate,
            USER_IDS.zhangHua,
            '张华审批',
            presidentOnly(),
          ),
        ),
      ),
      buildConditionNode(
        '默认部门负责人后院长',
        '其它人员：部门负责人后到院长',
        buildDefaultConditionSetting(),
        buildDeptLeaderApprove(approveTemplate, presidentOnly()),
      ),
    ],
  };
  return startNode;
}

function buildSavePayload(modelDetail, simpleModel) {
  return {
    id: modelDetail.id,
    key: modelDetail.key,
    name: modelDetail.name,
    category: modelDetail.category,
    icon: modelDetail.icon,
    description: modelDetail.description,
    type: modelDetail.type,
    formType: modelDetail.formType,
    formId: modelDetail.formId,
    formCustomCreatePath: modelDetail.formCustomCreatePath,
    formCustomViewPath: modelDetail.formCustomViewPath,
    visible: modelDetail.visible,
    startUserIds: modelDetail.startUserIds || [],
    startDeptIds: modelDetail.startDeptIds || [],
    managerUserIds: modelDetail.managerUserIds || [1],
    allowCancelRunningProcess: modelDetail.allowCancelRunningProcess,
    allowWithdrawTask: modelDetail.allowWithdrawTask,
    autoApprovalType: modelDetail.autoApprovalType ?? 0,
    simpleModel,
  };
}

function buildCreatePayload(referenceModel, newModel, simpleModel) {
  return {
    key: newModel.key,
    name: newModel.name,
    category: referenceModel.category,
    icon: referenceModel.icon,
    description: `${newModel.name}，按研究院实际组织架构配置审批链`,
    type: 20,
    formType: 20,
    formId: APPROVAL_FORM_ID,
    formCustomCreatePath: newModel.formCustomCreatePath,
    formCustomViewPath: newModel.formCustomViewPath,
    visible: true,
    startUserIds: [],
    startDeptIds: [],
    managerUserIds: referenceModel.managerUserIds || [1],
    allowCancelRunningProcess: referenceModel.allowCancelRunningProcess ?? true,
    allowWithdrawTask: referenceModel.allowWithdrawTask ?? true,
    autoApprovalType: referenceModel.autoApprovalType ?? 0,
    simpleModel,
  };
}

async function main() {
  const token = await login();
  log('登录成功');

  const approvalForm = await request('GET', `/bpm/form/get?id=${APPROVAL_FORM_ID}`, undefined, token);
  assert(approvalForm?.id === APPROVAL_FORM_ID, `审批表单 ${APPROVAL_FORM_ID} 不存在`);
  log('确认审批表单存在', { id: approvalForm.id, name: approvalForm.name });

  const list = await request('GET', '/bpm/model/list', undefined, token);
  const modelMap = new Map(list.map((item) => [item.key, item]));
  assert(EXISTING_MODEL_KEYS.every((key) => modelMap.has(key)), '现有 10 个流程模型不完整');

  const leaveDetail = await request(
    'GET',
    `/bpm/model/get?id=${modelMap.get('oa_leave').id}`,
    undefined,
    token,
  );
  const overtimeDetail = await request(
    'GET',
    `/bpm/model/get?id=${modelMap.get('oa_overtime').id}`,
    undefined,
    token,
  );

  assert(leaveDetail?.simpleModel?.id === 'StartUserNode', 'oa_leave SIMPLE 模型异常');
  const approveTemplate = findFirstApproveNode(overtimeDetail.simpleModel);

  const baseStartNode = leaveDetail.simpleModel;
  assert(baseStartNode?.id === 'StartUserNode', 'oa_leave SIMPLE 模型异常');
  assert(approveTemplate?.type === 11, '未找到可复用的审批节点模板');
  const targetSimpleModel = buildSpecialSimpleModel(baseStartNode, approveTemplate);

  for (const key of EXISTING_MODEL_KEYS) {
    const detail = await request(
      'GET',
      `/bpm/model/get?id=${modelMap.get(key).id}`,
      undefined,
      token,
    );
    const payload = buildSavePayload(detail, targetSimpleModel);
    await request('PUT', '/bpm/model/update', payload, token);
    log(`已更新模型 ${key}`, { id: detail.id, name: detail.name });
  }

  const newModelIds = [];
  for (const newModel of NEW_MODELS) {
    let modelId = modelMap.get(newModel.key)?.id;
    if (modelId) {
      const detail = await request('GET', `/bpm/model/get?id=${modelId}`, undefined, token);
      const payload = buildSavePayload(
        {
          ...detail,
          name: newModel.name,
          formType: 20,
          formId: APPROVAL_FORM_ID,
          formCustomCreatePath: newModel.formCustomCreatePath,
          formCustomViewPath: newModel.formCustomViewPath,
        },
        targetSimpleModel,
      );
      await request('PUT', '/bpm/model/update', payload, token);
      log(`已更新新模型 ${newModel.key}`, { id: modelId, name: newModel.name });
    } else {
      const payload = buildCreatePayload(overtimeDetail, newModel, targetSimpleModel);
      modelId = await request('POST', '/bpm/model/create', payload, token);
      log(`已创建新模型 ${newModel.key}`, { id: modelId, name: newModel.name });
    }
    newModelIds.push(modelId);
  }

  const deployIds = [
    ...EXISTING_MODEL_KEYS.map((key) => modelMap.get(key).id),
    ...newModelIds,
  ];

  for (const id of deployIds) {
    await request('POST', `/bpm/model/deploy?id=${id}`, undefined, token);
    log(`已部署模型 ${id}`);
  }

  const finalList = await request('GET', '/bpm/model/list', undefined, token);
  const finalKeys = finalList.map((item) => item.key);
  assert(finalKeys.includes('oa_leave_cancel'), '缺少 oa_leave_cancel');
  assert(finalKeys.includes('oa_outing'), '缺少 oa_outing');

  log('全部流程模型处理完成', {
    count: finalList.length,
    keys: finalKeys,
  });
}

main().catch((error) => {
  console.error(error.stack || error.message || error);
  process.exitCode = 1;
});
